using Amazon.Runtime;
using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using RAG.Application.Interfaces;
using RAG.Application.Interfaces.Pdfs;
using RAG.Domain;
using RAG.Domain.DTOs.Report;
using RAG.Domain.Enum;
using RAG.Infrastructure.Database;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;

namespace RAG.Infrastructure.Services
{
    public class ReportService : IReportService
    {
        private readonly ApplicationDbContext _context;
        private readonly IPdfExtractService _pdfExtractService;
        private readonly IS3Service _s3Service;
        private readonly ILogger<ReportService> _logger;
        private readonly long _maxFileSizeLimit;

        public ReportService(
            ApplicationDbContext context,
            IPdfExtractService pdfExtractService,
            IS3Service s3Service,
            IConfiguration configuration,
            ILogger<ReportService> logger)
        {
            _context = context;
            _pdfExtractService = pdfExtractService;
            _s3Service = s3Service;
            _logger = logger;
            _maxFileSizeLimit = configuration.GetValue<long>("FileUpload:MaxFileSizeMB", 50) * 1024 * 1024;
        }

        public async Task<UploadReportResponse> UploadReportAsync(UploadReportRequest request, Guid uploadedByUserId)
        {
            // 1. Validate File
            if (request.File == null || request.File.Length == 0)
            {
                throw new ArgumentException("File cannot be empty.");
            }

            if (request.File.Length > _maxFileSizeLimit)
            {
                throw new ArgumentException($"File size exceeds the limit of {_maxFileSizeLimit / 1024 / 1024} MB.");
            }

            if (request.File.ContentType != "application/pdf")
            {
                throw new ArgumentException("Only PDF files are allowed.");
            }

            // 2. Validate Foreign Keys (Company and Category)
            var companyExists = await _context.Companies.AnyAsync(c => c.Id == request.CompanyId);
            if (!companyExists) throw new ArgumentException("Company not found.");

            var categoryExists = await _context.ReportCategories.AnyAsync(c => c.Id == request.CategoryId);
            if (!categoryExists) throw new ArgumentException("Report Category not found.");

            // 3. Prevent Duplicates (Company, Category, Year, Period)
            var existingReport = await _context.ReportFinancials
                .FirstOrDefaultAsync(r => r.Companyid == request.CompanyId 
                                       && r.Categoryid == request.CategoryId 
                                       && r.Year == request.Year 
                                       && r.Period == request.Period);

            if (existingReport != null)
            {
                throw new InvalidOperationException($"A report for this company, category, year ({request.Year}), and period ({request.Period}) already exists.");
            }

            // 4. Extract PDF Content and Metrics
            var extractionResult = await _pdfExtractService.ExtractAllAsync(request.File);

            // Log PDF type để debug
            _logger.LogInformation($"PDF Type detected: {extractionResult.PdfType}");

            // Kiểm tra nếu là PDF ảnh
            if (extractionResult.PdfType == "ImageBased")
            {
                _logger.LogWarning("Image-based PDF detected. Using Gemini Vision for OCR processing.");
            }

            // 5. Upload file to S3 (FIXED: Now using S3 instead of local storage)
            byte[] fileBytes;
            using (var memoryStream = new MemoryStream())
            {
                await request.File.CopyToAsync(memoryStream);
                fileBytes = memoryStream.ToArray();
            }

            var fileName = $"{Guid.NewGuid()}_{request.File.FileName}";
            var s3FileUrl = await _s3Service.UploadFileAsync(fileBytes, fileName, "application/pdf");
            
            _logger.LogInformation($"PDF uploaded to S3: {s3FileUrl}");


            // 6. Save to Database using a Transaction
            using var transaction = await _context.Database.BeginTransactionAsync();
            try
            {
                var reportFinancial = new ReportFinancial
                {
                    Id = Guid.NewGuid(),
                    Companyid = request.CompanyId,
                    Categoryid = request.CategoryId,
                    Uploadedby = uploadedByUserId,
                    Year = request.Year,
                    Period = request.Period,
                    Filename = request.File.FileName,
                    Filesizekb = (int)(request.File.Length / 1024),
                    Fileurl = s3FileUrl, // ✅ Now using S3 URL
                    Contentraw = extractionResult.Text,
                    Visibility = string.IsNullOrEmpty(request.Visibility) ? "private" : request.Visibility,
                    Createdat = DateTime.SpecifyKind(DateTime.Now, DateTimeKind.Unspecified),
                    Updatedat = DateTime.SpecifyKind(DateTime.Now, DateTimeKind.Unspecified)
                };

                await _context.ReportFinancials.AddAsync(reportFinancial);

                var metricResponses = new List<MetricResponse>();

                if (extractionResult.Metrics != null && extractionResult.Metrics.Any())
                {
                    // Cache definitions to reduce DB calls
                    var definitionCodes = extractionResult.Metrics.Select(m => m.Code).Distinct().ToList();
                    var definitions = await _context.RatioDefinitions
                                                    .Where(d => definitionCodes.Contains(d.Code))
                                                    .ToDictionaryAsync(d => d.Code, d => d.Id);

                    foreach (var metric in extractionResult.Metrics)
                    {
                        if (definitions.TryGetValue(metric.Code, out Guid defId))
                        {
                            var ratioValue = new RatioValue
                            {
                                Id = Guid.NewGuid(),
                                Reportid = reportFinancial.Id,
                                Definitionid = defId,
                                Value = metric.Value,
                                Createdat = DateTime.SpecifyKind(DateTime.Now, DateTimeKind.Unspecified)
                            };
                            await _context.RatioValues.AddAsync(ratioValue);

                            metricResponses.Add(new MetricResponse
                            {
                                Code = metric.Code,
                                Name = metric.Name,
                                Value = metric.Value,
                                Unit = metric.Unit
                            });
                        }
                        else
                        {
                            _logger.LogWarning($"Ratio Definition for code '{metric.Code}' not found in DB. Skipped saving.");
                        }
                    }
                }

                await _context.SaveChangesAsync();
                await transaction.CommitAsync();

                return new UploadReportResponse
                {
                    ReportId = reportFinancial.Id,
                    Message = extractionResult.PdfType == "ImageBased" 
                        ? "Upload successful - Image-based PDF processed with Gemini Vision" 
                        : "Upload successful",
                    MetricsExtracted = metricResponses.Count,
                    PageCount = extractionResult.PageCount,
                    PdfType = extractionResult.PdfType, // NEW: Include PDF type in response
                    Metrics = metricResponses
                };
            }
            catch (Exception ex)
            {
                await transaction.RollbackAsync();
                _logger.LogError(ex, "Failed to save report and metrics to database.");
                // Note: S3 file cleanup could be added here if needed, but usually not necessary
                // since S3 has lifecycle policies and the file URL won't be saved to DB on failure
                throw;
            }
        }
        public async Task<GetOwnReport<MyReportItemDto>> GetMyReportsAsync(Guid userId, int page = 1, int pageSize = 10)
        {
            var query = _context.ReportFinancials
                .Include(r => r.Company)
                .Include(r => r.Category)
                .Where(r => r.Uploadedby == userId)
                .OrderByDescending(r => r.Createdat); 

            var total = await query.CountAsync();
            var data = await query
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(r => new MyReportItemDto
                {
                    Id = r.Id,
                    CompanyName = r.Company.Name,
                    Ticker = r.Company.Ticker,
                    CategoryName = r.Category.Name,
                    Year = r.Year,
                    Period = r.Period,
                    Visibility = r.Visibility,
                    FileName = r.Filename,
                    FileSizeKb = r.Filesizekb,
                    CreatedAt = r.Createdat
                })
                .ToListAsync();
            return new GetOwnReport<MyReportItemDto>
            {
                Total = total,
                Page = page,
                PageSize = pageSize,
                Data = data
            };
        }
        public async Task<GetOwnReport<MyReportItemDto>> GetPublicReportsAsync(int page = 1, int pageSize = 10)
        {
            var query = _context.ReportFinancials
                .Include(r => r.Company)
                .Include(r => r.Category)
                .Where(r => r.Visibility == "public")  
                .OrderByDescending(r => r.Createdat);

            var total = await query.CountAsync();
            var data = await query
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(r => new MyReportItemDto
                {
                    Id = r.Id,
                    CompanyName = r.Company.Name,
                    Ticker = r.Company.Ticker,
                    CategoryName = r.Category.Name,
                    Year = r.Year,
                    Period = r.Period,
                    Visibility = r.Visibility,
                    FileName = r.Filename,
                    FileSizeKb = r.Filesizekb,
                    CreatedAt = r.Createdat
                })
                .ToListAsync();

            return new GetOwnReport<MyReportItemDto>
            {
                Total = total,
                Page = page,
                PageSize = pageSize,
                Data = data
            };
        }
        public async Task<ReportDetailDto> GetReportByIdAsync(Guid reportId, Guid userId, string userRole)
        {
            var report = await _context.ReportFinancials
                .Include(r => r.Company)
                .Include(r => r.Category)
                .Include(r => r.UploadedbyNavigation)
                .Include(r => r.RatioValues)
                    .ThenInclude(rv => rv.Definition)
                .FirstOrDefaultAsync(r => r.Id == reportId);

            if (report == null)
            {
                throw new KeyNotFoundException("Report not found.");
            }
            if (userRole != SystemRoles.Admin)
            {
                if (report.Visibility != "public" && report.Uploadedby != userId)
                {
                    throw new UnauthorizedAccessException("You do not have permission to view this report.");
                }
            }

            // Map Entity sang DTO
            var metrics = report.RatioValues.Select(rv => new MetricResponse
            {
                Code = rv.Definition.Code,
                Name = rv.Definition.Name,
                Value = rv.Value ?? 0,
                Unit = rv.Definition.Unit ?? ""
            }).ToList();

            return new ReportDetailDto
            {
                Id = report.Id,
                Company = new CompanyBriefDto
                {
                    Id = report.Company.Id,
                    Ticker = report.Company.Ticker,
                    Name = report.Company.Name
                },
                CategoryName = report.Category.Name,
                Year = report.Year,
                Period = report.Period,
                FileUrl = report.Fileurl,
                FileName = report.Filename,
                FileSizeKb = report.Filesizekb,
                Visibility = report.Visibility,
                UploadedBy = new UserBriefDto
                {
                    Id = report.UploadedbyNavigation.Id,
                    FullName = report.UploadedbyNavigation.Fullname
                },
                CreatedAt = report.Createdat,
                Metrics = metrics
            };
        }
        public async Task<(string FilePath, string FileName)> DownloadReportAsync(Guid reportId, Guid userId, string userRole)
        {
            var report = await _context.ReportFinancials.FirstOrDefaultAsync(r => r.Id == reportId);

            if (report == null)
            {
                throw new KeyNotFoundException("Report not found.");
            }

            if (userRole != SystemRoles.Admin)
            {
                if (report.Visibility != "public" && report.Uploadedby != userId)
                {
                    throw new UnauthorizedAccessException("You do not have permission to download this report.");
                }
            }

            if (string.IsNullOrEmpty(report.Fileurl))
            {
                throw new FileNotFoundException("The file URL is empty in database.");
            }

            // ✅ FIXED: Generate presigned URL for secure S3 access
            var presignedUrl = await _s3Service.GeneratePresignedUrlAsync(report.Fileurl, 60); // 1 hour expiration
            return (presignedUrl, report.Filename ?? "Report.pdf");
        }
        public async Task<bool> UpdateVisibilityAsync(Guid reportId, string visibility, Guid userId, string userRole)
        {
            var report = await _context.ReportFinancials.FirstOrDefaultAsync(r => r.Id == reportId);
            if (report == null)
            {
                throw new KeyNotFoundException("Report not found.");
            }

            // Chỉ Owner hoặc Admin mới được phép Update
            if (userRole != SystemRoles.Admin && report.Uploadedby != userId)
            {
                throw new UnauthorizedAccessException("You do not have permission to update this report.");
            }

            var allowedVisibility = new[] { "public", "private" };
            if (!allowedVisibility.Contains(visibility.ToLower()))
            {
                throw new ArgumentException("Visibility must be 'public' or 'private'.");
            }

            report.Visibility = visibility.ToLower();
            report.Updatedat = DateTime.SpecifyKind(DateTime.Now, DateTimeKind.Unspecified);

            _context.ReportFinancials.Update(report);
            await _context.SaveChangesAsync();

            return true;
        }

        public async Task<bool> DeleteReportAsync(Guid reportId, Guid userId, string userRole)
        {
            var report = await _context.ReportFinancials.FirstOrDefaultAsync(r => r.Id == reportId);
            if (report == null)
            {
                throw new KeyNotFoundException("Report not found.");
            }

            // Chỉ Owner hoặc Admin mới được phép Xoá
            if (userRole != SystemRoles.Admin && report.Uploadedby != userId)
            {
                throw new UnauthorizedAccessException("You do not have permission to delete this report.");
            }

            using var transaction = await _context.Database.BeginTransactionAsync();
            try
            {
                // Cascade Delete: Thông thường khi xoá Report, Data ở RatioValue và Analytics (nếu có) cũng phải xoá theo
                // Tuy nhiên, nếu cấu hình DB đã có ON DELETE CASCADE, ta có thể bỏ qua bước xoá RatioValue thủ công
                var ratioValues = await _context.RatioValues.Where(rv => rv.Reportid == reportId).ToListAsync();
                if (ratioValues.Any())
                {
                    _context.RatioValues.RemoveRange(ratioValues);
                }

                _context.ReportFinancials.Remove(report);
                await _context.SaveChangesAsync();
                await transaction.CommitAsync();

                // Note: S3 file cleanup could be added here if needed
                // For now, we keep S3 files for audit/backup purposes
                // You can implement S3 file deletion if required:
                // await _s3Service.DeleteFileAsync(report.Fileurl);

                return true;
            }
            catch (Exception)
            {
                await transaction.RollbackAsync();
                throw;
            }
        }
        public async Task<GetOwnReport<ReportSearchDto>> SearchReportsAsync(string search, Guid? companyId, int? year, string? period, Guid userId, string userRole)
        {
            var query = _context.ReportFinancials.Include(r => r.Company).AsQueryable();

            // Lọc Permission (Chỉ lấy bài Public Hoặc của chính user đó nếu không phải Admin)
            if (userRole != SystemRoles.Admin)
            {
                query = query.Where(r => r.Visibility == "public" || r.Uploadedby == userId);
            }

            // Lọc theo keyword (Search trong Tên Công ty, Ticker, hoặc tên file)
            if (!string.IsNullOrWhiteSpace(search))
            {
                search = $"%{search.ToLower()}%";
                query = query.Where(r => EF.Functions.ILike(r.Company.Name, search) ||
                                         EF.Functions.ILike(r.Company.Ticker, search) ||
                                         EF.Functions.ILike(r.Filename, search));
            }

            // Lọc Optional Parameters
            if (companyId.HasValue) query = query.Where(r => r.Companyid == companyId.Value);
            if (year.HasValue) query = query.Where(r => r.Year == year.Value);
            if (!string.IsNullOrWhiteSpace(period)) query = query.Where(r => r.Period == period);

            var total = await query.CountAsync();

            var data = await query.Take(10).Select(r => new ReportSearchDto
            {
                Id = r.Id,
                Ticker = r.Company.Ticker,
                CompanyName = r.Company.Name,
                Year = r.Year,
                Period = r.Period,
                RelevanceScore = 1.0 
            }).ToListAsync();

            return new GetOwnReport<ReportSearchDto>
            {
                Total = total,
                Page = 1,
                PageSize = 10,
                Data = data
            };
        }
        public async Task<ReportMetricsDto> GetReportMetricsAsync(Guid reportId, Guid userId, string userRole)
        {
            var report = await _context.ReportFinancials.FirstOrDefaultAsync(r => r.Id == reportId);
            if (report == null)
            {
                throw new KeyNotFoundException("Report not found.");
            }

            // Phân quyền
            if (userRole != SystemRoles.Admin && report.Visibility != "public" && report.Uploadedby != userId)
            {
                throw new UnauthorizedAccessException("You do not have permission to view metrics for this report.");
            }

            var metrics = await _context.RatioValues
                .Include(rv => rv.Definition)
                    .ThenInclude(d => d.Group)
                .Where(rv => rv.Reportid == reportId)
                .Select(rv => new MetricDetailDto
                {
                    Id = rv.Id,
                    Code = rv.Definition.Code,
                    Name = rv.Definition.Name,
                    Value = rv.Value ?? 0,
                    Unit = rv.Definition.Unit,
                    GroupName = rv.Definition.Group.Name
                })
                .ToListAsync();

            return new ReportMetricsDto
            {
                ReportId = reportId,
                Metrics = metrics
            };
        }

    }
}

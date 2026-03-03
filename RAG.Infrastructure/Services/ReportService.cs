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
        private readonly ILogger<ReportService> _logger;
        private readonly long _maxFileSizeLimit;

        public ReportService(
            ApplicationDbContext context,
            IPdfExtractService pdfExtractService,
            IConfiguration configuration,
            ILogger<ReportService> logger)
        {
            _context = context;
            _pdfExtractService = pdfExtractService;
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

            // 5. Upload file logic (Mocking specific file storage: e.g. S3 here. For now, we will store locally or just save the name)
            var fileName = $"{Guid.NewGuid()}_{request.File.FileName}";
            var uploadDir = Path.Combine(Directory.GetCurrentDirectory(), "wwwroot", "uploads", "reports");
            if (!Directory.Exists(uploadDir)) Directory.CreateDirectory(uploadDir);
            
            var filePath = Path.Combine(uploadDir, fileName);
            using (var stream = new FileStream(filePath, FileMode.Create))
            {
                await request.File.CopyToAsync(stream);
            }
            var fileUrl = $"/uploads/reports/{fileName}"; // Replace with S3 URL when implemented


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
                    Fileurl = fileUrl,
                    Contentraw = extractionResult.Text,
                    Visibility = string.IsNullOrEmpty(request.Visibility) ? "private" : request.Visibility,
                    Createdat = DateTime.Now,
                    Updatedat = DateTime.Now
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
                                Createdat = DateTime.Now
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
                    Message = "Upload successful",
                    MetricsExtracted = metricResponses.Count,
                    PageCount = extractionResult.PageCount,
                    Metrics = metricResponses
                };
            }
            catch (Exception ex)
            {
                await transaction.RollbackAsync();
                _logger.LogError(ex, "Failed to save report and metrics to database.");
                // Cleanup file if DB save fails
                if (System.IO.File.Exists(filePath))
                {
                    System.IO.File.Delete(filePath);
                }
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

    }
}

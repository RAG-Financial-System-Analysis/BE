using Microsoft.EntityFrameworkCore;
using RAG.Application.Interfaces;
using RAG.Application.Interfaces.Analaytic;
using RAG.Domain;
using RAG.Domain.DTOs.Analytic;
using RAG.Infrastructure.Database;
using System;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace RAG.Infrastructure.Services
{
    public class AnalyticsService : IAnalyticsService
    {
        private readonly ApplicationDbContext _dbContext;
        private readonly IS3Service _s3Service;

        public AnalyticsService(ApplicationDbContext dbContext, IS3Service s3Service)
        {
            _dbContext = dbContext;
            _s3Service = s3Service;
        }

        public async Task<GetAnalyticTypeResponse> GetAnalyticTypesAsync()
        {
            var types = await _dbContext.AnalyticsTypes
                .Select(t => new AnalyticTypeDto
                {
                    Id = t.Id,
                    Code = t.Code,
                    Name = t.Name,
                    Description = t.Description
                })
                .ToListAsync();

            return new GetAnalyticTypeResponse
            {
                AnalyticTypes = types
            };
        }

        public async Task<GenerateAnalyticsReportResponse> GenerateAnalyticsReportAsync(GenerateAnalyticsReportRequest request, Guid userId)
        {
            // 1. Mock Report Generation Content (In a real app, you would call OpenAI here based on the SessionId and ReportFinancialId)
            var generatedContent = $@"
            {{
                ""summary"": ""This is an automatically generated analytics report."",
                ""session_id"": ""{request.SessionId}"",
                ""financial_id"": ""{request.ReportFinancialId}"",
                ""generated_at"": ""{DateTime.UtcNow:O}""
            }}";

            // 2. Upload to S3 as JSON
            var fileData = Encoding.UTF8.GetBytes(generatedContent);
            var fileName = $"report_{request.ReportFinancialId}.json";
            var fileUrl = await _s3Service.UploadFileAsync(fileData, fileName, "application/json");

            // 3. Save to Database
            var report = new AnalyticsReport
            {
                Id = Guid.NewGuid(),
                Title = request.Title,
                Sessionid = request.SessionId,
                Reportfinancialid = request.ReportFinancialId,
                Generatedcontent = generatedContent,
                Fileurl = fileUrl,
                Generationtype = "auto",
                Generatedby = userId,
                Createdat = DateTime.SpecifyKind(DateTime.Now, DateTimeKind.Unspecified)
            };

            _dbContext.AnalyticsReports.Add(report);
            await _dbContext.SaveChangesAsync();

            return new GenerateAnalyticsReportResponse
            {
                ReportId = report.Id,
                Message = "Analytics report generated successfully",
                FileUrl = fileUrl
            };
        }

        public async Task<GetAnalyticsReportsResponse> GetAnalyticsReportsAsync(Guid? sessionId, int page, int pageSize)
        {
            var query = _dbContext.AnalyticsReports.AsQueryable();

            if (sessionId.HasValue)
            {
                query = query.Where(r => r.Sessionid == sessionId.Value);
            }

            var total = await query.CountAsync();

            var data = await query
                .OrderByDescending(r => r.Createdat)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(r => new AnalyticsReportItemDto
                {
                    Id = r.Id,
                    Title = r.Title ?? string.Empty,
                    SessionId = r.Sessionid ?? Guid.Empty,
                    FileUrl = r.Fileurl ?? string.Empty,
                    GenerationType = r.Generationtype ?? string.Empty,
                    CreatedAt = r.Createdat ?? DateTime.MinValue
                })
                .ToListAsync();

            return new GetAnalyticsReportsResponse
            {
                Total = total,
                Page = page,
                PageSize = pageSize,
                Data = data
            };
        }

        public async Task<GetAnalyticsReportByIdResponse> GetAnalyticsReportByIdAsync(Guid id)
        {
            var report = await _dbContext.AnalyticsReports
                .Include(r => r.GeneratedbyNavigation)
                .FirstOrDefaultAsync(r => r.Id == id);

            if (report == null)
            {
                throw new Exception("Analytics report not found");
            }

            return new GetAnalyticsReportByIdResponse
            {
                Id = report.Id,
                Title = report.Title ?? string.Empty,
                SessionId = report.Sessionid ?? Guid.Empty,
                ReportFinancialId = report.Reportfinancialid ?? Guid.Empty,
                GeneratedContent = report.Generatedcontent ?? string.Empty,
                FileUrl = report.Fileurl ?? string.Empty,
                GenerationType = report.Generationtype ?? string.Empty,
                CreatedAt = report.Createdat ?? DateTime.MinValue,
                GeneratedBy = report.GeneratedbyNavigation != null ? new GeneratedByDto
                {
                    Id = report.GeneratedbyNavigation.Id,
                    FullName = report.GeneratedbyNavigation.Fullname ?? string.Empty
                } : null
            };
        }
    }
}

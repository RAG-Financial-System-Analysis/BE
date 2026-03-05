using RAG.Domain.DTOs.Analytic;
using System;
using System.Threading.Tasks;

namespace RAG.Application.Interfaces.Analaytic
{
    public interface IAnalyticsService
    {
        Task<GetAnalyticTypeResponse> GetAnalyticTypesAsync();
        Task<GenerateAnalyticsReportResponse> GenerateAnalyticsReportAsync(GenerateAnalyticsReportRequest request, Guid userId);
        Task<GetAnalyticsReportsResponse> GetAnalyticsReportsAsync(Guid? sessionId, int page, int pageSize);
        Task<GetAnalyticsReportByIdResponse> GetAnalyticsReportByIdAsync(Guid id);
    }
}

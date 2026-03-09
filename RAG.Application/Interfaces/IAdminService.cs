using RAG.Domain;
using RAG.Domain.DTOs.Admin;
using System;
using System.Threading.Tasks;

namespace RAG.Application.Interfaces
{
    public interface IAdminService
    {
        Task<GetAuditLogsResponse> GetAuditLogsAsync(Guid? userId, string action, DateTime? startDate, DateTime? endDate, int page, int pageSize);
        Task<SystemStatisticsResponse> GetSystemStatisticsAsync();
        Task<CreateReportCategoriesResponse> CreateReportCategoryAsync(CreateReportCategoriesRequest request);
        Task<GetReportCategoriesResponse> GetReportCategoriesAsync(int page, int pageSize);
        Task<GetReportCategoryByIdResponse> GetReportCategoryByIdAsync(Guid id);
        Task UpdateReportCategoryAsync(Guid id, UpdateReportCategoryRequest request);
        Task DeleteReportCategoryAsync(Guid id);
        Task<GetReportCategoriesForAnalystResponse> GetReportCategoriesForAnalystAsync();
        Task<CreateAnalyticsTypeResponse> CreateAnalyticsTypeAsync(CreateAnalyticsTypeRequest request);
        Task UpdateAnalyticsTypeAsync(Guid id, UpdateAnalyticsTypeRequest request);
        Task DeleteAnalyticsTypeAsync(Guid id);
    }
}

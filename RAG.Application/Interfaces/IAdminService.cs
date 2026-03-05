using RAG.Domain.DTOs.Admin;
using System;
using System.Threading.Tasks;

namespace RAG.Application.Interfaces
{
    public interface IAdminService
    {
        Task<GetAuditLogsResponse> GetAuditLogsAsync(Guid? userId, string action, DateTime? startDate, DateTime? endDate, int page, int pageSize);
        Task<SystemStatisticsResponse> GetSystemStatisticsAsync();
    }
}

using RAG.Domain.DTOs.Metric;
using System;
using System.Threading.Tasks;

namespace RAG.Application.Interfaces
{
    public interface IMetricService
    {
        Task<GetMetricGroupsResponse> GetMetricGroupsAsync();
        Task<GetMetricDefinitionsResponse> GetMetricDefinitionsAsync(Guid? groupId);
        Task<GetMetricValuesByReportResponse> GetMetricValuesByReportAsync(Guid reportId);
        Task<CalculateMetricsResponse> CalculateMetricsAsync(CalculateMetricsRequest request);
    }
}

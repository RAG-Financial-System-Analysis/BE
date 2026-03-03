using RAG.Domain.DTOs.Report;
using System.Threading.Tasks;

namespace RAG.Application.Interfaces
{
    public interface IReportService
    {
        Task<UploadReportResponse> UploadReportAsync(UploadReportRequest request, Guid uploadedByUserId);

        Task<GetOwnReport<MyReportItemDto>> GetMyReportsAsync(Guid userId, int page = 1, int pageSize = 10);

        Task<GetOwnReport<MyReportItemDto>> GetPublicReportsAsync(int page = 1, int pageSize = 10);

        Task<ReportDetailDto> GetReportByIdAsync(Guid reportId, Guid userId, string userRole);

        Task<(string FilePath, string FileName)> DownloadReportAsync(Guid reportId, Guid userId, string userRole);

        Task<bool> UpdateVisibilityAsync(Guid reportId, string visibility, Guid userId, string userRole);

        Task<bool> DeleteReportAsync(Guid reportId, Guid userId, string userRole);

        Task<GetOwnReport<ReportSearchDto>> SearchReportsAsync(string search, Guid? companyId, int? year, string? period, Guid userId, string userRole);

        Task<ReportMetricsDto> GetReportMetricsAsync(Guid reportId, Guid userId, string userRole);
    }
}

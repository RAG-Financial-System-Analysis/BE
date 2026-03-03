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

    }
}

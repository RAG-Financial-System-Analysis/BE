using RAG.Domain.DTOs.Report;
using System.Threading.Tasks;

namespace RAG.Application.Interfaces
{
    public interface IReportService
    {
        Task<UploadReportResponse> UploadReportAsync(UploadReportRequest request, Guid uploadedByUserId);
    }
}

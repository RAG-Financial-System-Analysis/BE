using Microsoft.AspNetCore.Http;
using RAG.Domain.DTOs.Pdfs;

namespace RAG.Application.Interfaces.Pdfs
{
    public interface IPdfExtractService
    {
        Task<ExtractResultDto> ExtractAllAsync(IFormFile file);
    }
}

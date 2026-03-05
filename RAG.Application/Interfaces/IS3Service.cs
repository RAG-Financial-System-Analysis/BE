using System.Threading.Tasks;

namespace RAG.Application.Interfaces
{
    public interface IS3Service
    {
        Task<string> UploadFileAsync(byte[] fileData, string fileName, string contentType);
    }
}

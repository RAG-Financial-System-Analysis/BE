using System.Threading.Tasks;

namespace RAG.Application.Interfaces
{
    public interface IS3Service
    {
        Task<string> UploadFileAsync(byte[] fileData, string fileName, string contentType);
        Task<string> GeneratePresignedUrlAsync(string s3Url, int expirationMinutes = 60);
    }
}

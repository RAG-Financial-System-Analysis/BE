using System.Threading.Tasks;

namespace RAG.Application.Interfaces
{
    public interface IS3Service
    {
        Task<string> UploadFileAsync(byte[] fileData, string fileName, string contentType);
        Task<string> UploadJobFileAsync(byte[] fileData, string fileName, string contentType);
        Task<string> GeneratePresignedUrlAsync(string s3Url, int expirationMinutes = 60);
        
        // NEW: JSON operations for job system
        Task PutJsonAsync<T>(string key, T data);
        Task<T?> GetJsonAsync<T>(string key);
        Task<byte[]> DownloadFileAsync(string s3UrlOrKey);
    }
}

using Amazon.S3;
using Amazon.S3.Model;
using Microsoft.Extensions.Configuration;
using RAG.Application.Interfaces;
using System;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;

namespace RAG.Infrastructure.AWS.Implements
{
    public class S3Service : IS3Service
    {
        private readonly IAmazonS3 _s3Client;
        private readonly string _bucketName;

        public S3Service(IAmazonS3 s3Client, IConfiguration configuration)
        {
            _s3Client = s3Client;
            _bucketName = configuration["AWS:S3BucketName"] ?? throw new ArgumentNullException("S3BucketName is missing in configuration");
        }

        public async Task<string> UploadFileAsync(byte[] fileData, string fileName, string contentType)
        {
            var key = $"reports/{Guid.NewGuid()}_{fileName}"; // ✅ FIXED: Use reports folder instead of analytics

            using var stream = new MemoryStream(fileData);
            
            var putRequest = new PutObjectRequest
            {
                BucketName = _bucketName,
                Key = key,
                InputStream = stream,
                ContentType = contentType,
                // Optional: Caclulate and Set ACLs or CannedACL if needed but depends on Bucket Policy
            };

            var response = await _s3Client.PutObjectAsync(putRequest);
            
            if (response.HttpStatusCode == System.Net.HttpStatusCode.OK)
            {
                // Generate public URL format
                return $"https://{_bucketName}.s3.amazonaws.com/{key}";
            }
            
            throw new Exception("Error uploading file to S3");
        }

        // NEW: Upload file for job processing (returns key, not URL)
        public async Task<string> UploadJobFileAsync(byte[] fileData, string fileName, string contentType)
        {
            var key = $"jobs/{Guid.NewGuid()}/input.pdf";

            using var stream = new MemoryStream(fileData);
            
            var putRequest = new PutObjectRequest
            {
                BucketName = _bucketName,
                Key = key,
                InputStream = stream,
                ContentType = contentType
            };

            var response = await _s3Client.PutObjectAsync(putRequest);
            
            if (response.HttpStatusCode == System.Net.HttpStatusCode.OK)
            {
                // Return key only (not full URL) for job processing
                return key;
            }
            
            throw new Exception("Error uploading job file to S3");
        }

        public async Task<string> GeneratePresignedUrlAsync(string s3Url, int expirationMinutes = 60)
        {
            try
            {
                Console.WriteLine($"🔍 DEBUG: Input S3 URL: {s3Url}");
                
                // Extract key from S3 URL
                var uri = new Uri(s3Url);
                var key = uri.AbsolutePath.TrimStart('/');
                
                Console.WriteLine($"🔍 DEBUG: Extracted key: {key}");
                Console.WriteLine($"🔍 DEBUG: Bucket name: {_bucketName}");

                var request = new GetPreSignedUrlRequest
                {
                    BucketName = _bucketName,
                    Key = key,
                    Verb = HttpVerb.GET,
                    Expires = DateTime.UtcNow.AddMinutes(expirationMinutes)
                };

                var presignedUrl = await _s3Client.GetPreSignedURLAsync(request);
                
                Console.WriteLine($"✅ DEBUG: Generated presigned URL: {presignedUrl}");
                
                return presignedUrl;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"❌ DEBUG: Error generating presigned URL: {ex.Message}");
                Console.WriteLine($"❌ DEBUG: Stack trace: {ex.StackTrace}");
                throw new Exception($"Error generating presigned URL: {ex.Message}", ex);
            }
        }

        // NEW: JSON operations for job system
        public async Task PutJsonAsync<T>(string key, T data)
        {
            var json = JsonSerializer.Serialize(data, new JsonSerializerOptions { WriteIndented = true });
            var bytes = Encoding.UTF8.GetBytes(json);

            using var stream = new MemoryStream(bytes);
            
            var putRequest = new PutObjectRequest
            {
                BucketName = _bucketName,
                Key = key,
                InputStream = stream,
                ContentType = "application/json"
            };

            var response = await _s3Client.PutObjectAsync(putRequest);
            
            if (response.HttpStatusCode != System.Net.HttpStatusCode.OK)
            {
                throw new Exception($"Error uploading JSON to S3: {response.HttpStatusCode}");
            }
        }

        public async Task<T?> GetJsonAsync<T>(string key)
        {
            try
            {
                var getRequest = new GetObjectRequest
                {
                    BucketName = _bucketName,
                    Key = key
                };

                using var response = await _s3Client.GetObjectAsync(getRequest);
                using var reader = new StreamReader(response.ResponseStream);
                
                var json = await reader.ReadToEndAsync();
                return JsonSerializer.Deserialize<T>(json);
            }
            catch (AmazonS3Exception ex) when (ex.StatusCode == System.Net.HttpStatusCode.NotFound)
            {
                throw new FileNotFoundException($"S3 object not found: {key}");
            }
        }

        public async Task<byte[]> DownloadFileAsync(string s3UrlOrKey)
        {
            try
            {
                string key;
                
                // Check if input is a full S3 URL or just a key
                if (s3UrlOrKey.StartsWith("https://"))
                {
                    // Extract key from S3 URL
                    var uri = new Uri(s3UrlOrKey);
                    key = uri.AbsolutePath.TrimStart('/');
                }
                else
                {
                    // It's already a key
                    key = s3UrlOrKey;
                }

                var getRequest = new GetObjectRequest
                {
                    BucketName = _bucketName,
                    Key = key
                };

                using var response = await _s3Client.GetObjectAsync(getRequest);
                using var memoryStream = new MemoryStream();
                
                await response.ResponseStream.CopyToAsync(memoryStream);
                return memoryStream.ToArray();
            }
            catch (AmazonS3Exception ex) when (ex.StatusCode == System.Net.HttpStatusCode.NotFound)
            {
                throw new FileNotFoundException($"S3 file not found: {s3UrlOrKey}");
            }
        }
    }
}

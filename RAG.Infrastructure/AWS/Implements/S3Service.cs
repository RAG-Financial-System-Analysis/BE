using Amazon.S3;
using Amazon.S3.Model;
using Microsoft.Extensions.Configuration;
using RAG.Application.Interfaces;
using System;
using System.IO;
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
            var key = $"analytics/{Guid.NewGuid()}_{fileName}";

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
    }
}

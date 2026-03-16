using Microsoft.AspNetCore.Mvc;
using RAG.Application.Interfaces;

namespace RAG.APIs.Controllers
{
    [Route("api/test")]
    [ApiController]
    public class TestController : ControllerBase
    {
        private readonly IS3Service _s3Service;

        public TestController(IS3Service s3Service)
        {
            _s3Service = s3Service;
        }

        [HttpPost("s3-upload")]
        [Consumes("multipart/form-data")]
        public async Task<IActionResult> TestS3Upload(IFormFile file)
        {
            try
            {
                if (file == null || file.Length == 0)
                {
                    return BadRequest("No file provided");
                }

                // Convert to bytes
                byte[] fileBytes;
                using (var memoryStream = new MemoryStream())
                {
                    await file.CopyToAsync(memoryStream);
                    fileBytes = memoryStream.ToArray();
                }

                // Test job upload
                var jobKey = await _s3Service.UploadJobFileAsync(fileBytes, file.FileName, file.ContentType);
                
                // Test download
                var downloadedBytes = await _s3Service.DownloadFileAsync(jobKey);

                return Ok(new
                {
                    message = "S3 upload/download test successful",
                    jobKey = jobKey,
                    originalSize = fileBytes.Length,
                    downloadedSize = downloadedBytes.Length,
                    sizesMatch = fileBytes.Length == downloadedBytes.Length
                });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { 
                    message = "S3 test failed", 
                    error = ex.Message,
                    stackTrace = ex.StackTrace
                });
            }
        }

        [HttpGet("s3-info")]
        public IActionResult GetS3Info()
        {
            return Ok(new
            {
                message = "S3 service is available",
                timestamp = DateTime.UtcNow
            });
        }
    }
}
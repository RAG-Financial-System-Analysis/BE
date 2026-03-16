using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RAG.Application.Interfaces;
using RAG.Domain.DTOs.Report;
using RAG.Domain.DTOs.Job;
using RAG.Domain.Enum;
using RAG.Infrastructure.Services;
using System.Security.Claims;

namespace RAG.APIs.Controllers
{
    [Route("api/reports")]
    [ApiController]
    public class ReportsController : ControllerBase
    {
        private readonly IReportService _reportService;
        private readonly IJobService _jobService;
        private readonly IS3Service _s3Service;
        private readonly IBackgroundTaskQueue _taskQueue;

        public ReportsController(IReportService reportService, IJobService jobService, IS3Service s3Service, IBackgroundTaskQueue taskQueue)
        {
            _reportService = reportService;
            _jobService = jobService;
            _s3Service = s3Service;
            _taskQueue = taskQueue;
        }

        [HttpPost("upload")]
        [Authorize(Roles = $"{SystemRoles.Admin},{SystemRoles.Analyst}")]
        [Consumes("multipart/form-data")]
        public async Task<IActionResult> UploadReport([FromForm] UploadReportRequest request)
        {
            try
            {
                var userIdClaim = User.FindFirst("internal_user_id")?.Value;
                if (string.IsNullOrEmpty(userIdClaim))
                {
                    return Unauthorized("User is not authenticated or Sub is missing.");
                }
                if (!Guid.TryParse(userIdClaim, out Guid internalUserId))
                {
                    return BadRequest("User id claim is not a valid GUID. Have you configured ClaimsTransformation?");
                }

                var response = await _reportService.UploadReportAsync(request, internalUserId);
                return Ok(response);
            }
            catch (ArgumentException ex)
            {
                return BadRequest(new { Message = ex.Message });
            }
            catch (InvalidOperationException ex)
            {
                return Conflict(new { Message = ex.Message });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while uploading the report.", Details = ex.Message });
            }
        }

        [HttpPost("upload-async")]
        [Authorize(Roles = $"{SystemRoles.Admin},{SystemRoles.Analyst}")]
        [Consumes("multipart/form-data")]
        public async Task<IActionResult> UploadReportAsync([FromForm] UploadReportRequest request)
        {
            try
            {
                var userIdClaim = User.FindFirst("internal_user_id")?.Value;
                if (string.IsNullOrEmpty(userIdClaim))
                {
                    return Unauthorized("User is not authenticated or Sub is missing.");
                }
                if (!Guid.TryParse(userIdClaim, out Guid internalUserId))
                {
                    return BadRequest("User id claim is not a valid GUID. Have you configured ClaimsTransformation?");
                }

                // Quick validations only
                if (request.File == null || request.File.Length == 0)
                {
                    return BadRequest(new { Message = "File cannot be empty." });
                }

                if (request.File.ContentType != "application/pdf")
                {
                    return BadRequest(new { Message = "Only PDF files are allowed." });
                }

                // Upload file to S3 first (for job processing)
                byte[] fileBytes;
                using (var memoryStream = new MemoryStream())
                {
                    await request.File.CopyToAsync(memoryStream);
                    fileBytes = memoryStream.ToArray();
                }

                var s3Key = await _s3Service.UploadJobFileAsync(fileBytes, request.File.FileName, "application/pdf");

                // Create job with input data
                var inputData = new
                {
                    S3Key = s3Key,
                    FileName = request.File.FileName,
                    CompanyId = request.CompanyId,
                    CategoryId = request.CategoryId,
                    Year = request.Year,
                    Period = request.Period,
                    Visibility = request.Visibility ?? "private"
                };

                var jobId = await _jobService.CreateJobAsync("upload", internalUserId, inputData);

                // Queue background job processing
                await _taskQueue.QueueBackgroundWorkItemAsync(async token =>
                {
                    using var scope = HttpContext.RequestServices.CreateScope();
                    var backgroundService = scope.ServiceProvider.GetRequiredService<BackgroundJobService>();
                    await backgroundService.ProcessUploadJobAsync(jobId);
                });

                return Ok(new AsyncUploadResponse
                {
                    JobId = jobId,
                    Status = "pending",
                    Message = "Upload started. Use jobId to check progress."
                });
            }
            catch (ArgumentException ex)
            {
                return BadRequest(new { Message = ex.Message });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while starting the upload.", Details = ex.Message });
            }
        }
        [HttpGet("my-reports")]
        [Authorize(Roles = $"{SystemRoles.Admin},{SystemRoles.Analyst}")]
        public async Task<IActionResult> GetMyReports([FromQuery] int page = 1, [FromQuery] int pageSize = 10)
        {
            try
            {
                var userIdClaim = User.FindFirst("internal_user_id")?.Value;
                if (string.IsNullOrEmpty(userIdClaim))
                {
                    return Unauthorized("User is not authenticated or Sub is missing.");
                }

                if (!Guid.TryParse(userIdClaim, out Guid internalUserId))
                {
                    return BadRequest("User id claim is not a valid GUID.");
                }
                if (page < 1) page = 1;
                if (pageSize < 1) pageSize = 10;
                var response = await _reportService.GetMyReportsAsync(internalUserId, page, pageSize);
                return Ok(response);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while fetching your reports.", Details = ex.Message });
            }
        }
        [HttpGet("public-reports")]
        [Authorize(Roles = $"{SystemRoles.Admin},{SystemRoles.Analyst}")]
        public async Task<IActionResult> GetPublicReports([FromQuery] int page = 1, [FromQuery] int pageSize = 10)
        {
            try
            {
                if (page < 1) page = 1;
                if (pageSize < 1) pageSize = 10;
                var response = await _reportService.GetPublicReportsAsync(page, pageSize);
                return Ok(response);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while fetching public reports.", Details = ex.Message });
            }
        }
        [HttpGet("{id}")]
        [Authorize(Roles = $"{SystemRoles.Admin},{SystemRoles.Analyst}")]
        public async Task<IActionResult> GetReportById(Guid id)
        {
            try
            {
                var userIdClaim = User.FindFirst("internal_user_id")?.Value;
                var roleClaim = User.FindFirst(ClaimTypes.Role)?.Value;

                if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out Guid internalUserId))
                {
                    return Unauthorized("User is not authenticated.");
                }

                var response = await _reportService.GetReportByIdAsync(id, internalUserId, roleClaim ?? "");
                return Ok(response);
            }
            catch (KeyNotFoundException ex)
            {
                return NotFound(new { Message = ex.Message });
            }
            catch (UnauthorizedAccessException ex)
            {
                return StatusCode(403, new { Message = ex.Message });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while fetching the report.", Details = ex.Message });
            }
        }
        [HttpGet("{id}/download")]
        [Authorize(Roles = $"{SystemRoles.Admin},{SystemRoles.Analyst}")]
        public async Task<IActionResult> DownloadReportPdf(Guid id)
        {
            try
            {
                var userIdClaim = User.FindFirst("internal_user_id")?.Value;
                var roleClaim = User.FindFirst(ClaimTypes.Role)?.Value;

                if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out Guid internalUserId))
                {
                    return Unauthorized("User is not authenticated.");
                }

                var (presignedUrl, fileName) = await _reportService.DownloadReportAsync(id, internalUserId, roleClaim ?? "");

                // ✅ NEW: Return JSON with download URL instead of redirect
                return Ok(new { 
                    downloadUrl = presignedUrl, 
                    fileName = fileName,
                    message = "Download URL generated successfully" 
                });
            }
            // 404 Not Found (Từ Service hoặc Controller)
            catch (KeyNotFoundException ex)
            {
                return NotFound(new { Message = ex.Message });
            }
            catch (FileNotFoundException ex)
            {
                return NotFound(new { Message = ex.Message });
            }
            // 403 Forbidden
            catch (UnauthorizedAccessException ex)
            {
                return StatusCode(403, new { Message = ex.Message });
            }
            // 500 Lỗi Internal
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while downloading the report.", Details = ex.Message });
            }
        }
        [HttpPatch("{id}/visibility")]
        [Authorize(Roles = $"{SystemRoles.Admin},{SystemRoles.Analyst}")]
        public async Task<IActionResult> UpdateVisibility(Guid id, [FromBody] UpdateVisibilityRequest request)
        {
            try
            {
                var userIdClaim = User.FindFirst("internal_user_id")?.Value;
                var roleClaim = User.FindFirst(ClaimTypes.Role)?.Value;

                if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out Guid internalUserId))
                {
                    return Unauthorized("User is not authenticated.");
                }

                await _reportService.UpdateVisibilityAsync(id, request.Visibility, internalUserId, roleClaim ?? "");
                return Ok(new { Message = "Visibility updated successfully" });
            }
            catch (KeyNotFoundException ex)
            {
                return NotFound(new { Message = ex.Message });
            }
            catch (ArgumentException ex) // Bắt lỗi validation input string
            {
                return BadRequest(new { Message = ex.Message });
            }
            catch (UnauthorizedAccessException ex)
            {
                return StatusCode(403, new { Message = ex.Message });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while updating visibility.", Details = ex.Message });
            }
        }

        [HttpDelete("{id}")]
        [Authorize(Roles = $"{SystemRoles.Admin},{SystemRoles.Analyst}")]
        public async Task<IActionResult> DeleteReport(Guid id)
        {
            try
            {
                var userIdClaim = User.FindFirst("internal_user_id")?.Value;
                var roleClaim = User.FindFirst(ClaimTypes.Role)?.Value;

                if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out Guid internalUserId))
                {
                    return Unauthorized("User is not authenticated.");
                }

                await _reportService.DeleteReportAsync(id, internalUserId, roleClaim ?? "");
                return Ok(new { Message = "Report deleted successfully" });
            }
            catch (KeyNotFoundException ex)
            {
                return NotFound(new { Message = ex.Message });
            }
            catch (UnauthorizedAccessException ex)
            {
                return StatusCode(403, new { Message = ex.Message });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while deleting the report.", Details = ex.Message });
            }
        }
        [HttpGet("search")]
        [Authorize(Roles = $"{SystemRoles.Admin},{SystemRoles.Analyst}")]
        public async Task<IActionResult> SearchReports([FromQuery] string? query, [FromQuery] Guid? companyId, [FromQuery] int? year, [FromQuery] string? period)
        {
            try
            {
                var userIdClaim = User.FindFirst("internal_user_id")?.Value;
                var roleClaim = User.FindFirst(ClaimTypes.Role)?.Value;

                if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out Guid internalUserId))
                {
                    return Unauthorized("User is not authenticated.");
                }

                var response = await _reportService.SearchReportsAsync(query ?? "", companyId, year, period, internalUserId, roleClaim ?? "");
                return Ok(response);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while searching reports.", Details = ex.Message });
            }
        }
        [HttpGet("{id}/metrics")]
        [Authorize(Roles = $"{SystemRoles.Admin},{SystemRoles.Analyst}")]
        public async Task<IActionResult> GetReportMetrics(Guid id)
        {
            try
            {
                var userIdClaim = User.FindFirst("internal_user_id")?.Value;
                var roleClaim = User.FindFirst(ClaimTypes.Role)?.Value;

                if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out Guid internalUserId))
                {
                    return Unauthorized();
                }

                var response = await _reportService.GetReportMetricsAsync(id, internalUserId, roleClaim ?? "");
                return Ok(response);
            }
            catch (KeyNotFoundException ex)
            {
                return NotFound(new { Message = ex.Message });
            }
            catch (UnauthorizedAccessException ex)
            {
                return StatusCode(403, new { Message = ex.Message });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred fetching metrics.", Details = ex.Message });
            }
        }

    }
}

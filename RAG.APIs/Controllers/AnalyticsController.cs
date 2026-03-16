using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RAG.Application.Interfaces;
using RAG.Application.Interfaces.Analaytic;
using RAG.Domain.DTOs.Analytic;
using RAG.Domain.Enum;
using RAG.Infrastructure.Services;
using System;
using System.Threading.Tasks;

namespace RAG.APIs.Controllers
{
    [Route("api/analytics")]
    [ApiController]
    public class AnalyticsController : ControllerBase
    {
        private readonly IAnalyticsService _analyticsService;
        private readonly IJobService _jobService;
        private readonly IBackgroundTaskQueue _backgroundTaskQueue;
        private readonly IServiceProvider _serviceProvider;

        public AnalyticsController(
            IAnalyticsService analyticsService,
            IJobService jobService,
            IBackgroundTaskQueue backgroundTaskQueue,
            IServiceProvider serviceProvider)
        {
            _analyticsService = analyticsService;
            _jobService = jobService;
            _backgroundTaskQueue = backgroundTaskQueue;
            _serviceProvider = serviceProvider;
        }

        [HttpGet("types")]
        [Authorize(Roles = $"{SystemRoles.Admin},{SystemRoles.Analyst}")]
        public async Task<IActionResult> GetAnalyticsTypes()
        {
            try
            {
                var response = await _analyticsService.GetAnalyticTypesAsync();
                return Ok(response);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while getting analytics types.", Details = ex.Message });
            }
        }

        [HttpPost("generate")]
        [Authorize(Roles = $"{SystemRoles.Admin},{SystemRoles.Analyst}")]
        public async Task<IActionResult> GenerateAnalyticsReport([FromBody] GenerateAnalyticsReportRequest request)
        {
            try
            {
                // Validate model
                if (!ModelState.IsValid)
                {
                    return BadRequest(ModelState);
                }

                var userIdString = User.FindFirst("internal_user_id")?.Value;
                if (string.IsNullOrEmpty(userIdString) || !Guid.TryParse(userIdString, out Guid userId))
                {
                    return Unauthorized(new { Message = "Invalid or missing user ID in token." });
                }

                var response = await _analyticsService.GenerateAnalyticsReportAsync(request, userId);
                return Ok(response);
            }
            catch (ArgumentException ex)
            {
                return BadRequest(new { Message = ex.Message });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while generating the analytics report.", Details = ex.Message });
            }
        }

        [HttpPost("generate-async")]
        [Authorize(Roles = $"{SystemRoles.Admin},{SystemRoles.Analyst}")]
        public async Task<IActionResult> GenerateAnalyticsReportAsync([FromBody] GenerateAnalyticsReportRequest request)
        {
            try
            {
                // Validate model
                if (!ModelState.IsValid)
                {
                    return BadRequest(ModelState);
                }

                var userIdString = User.FindFirst("internal_user_id")?.Value;
                if (string.IsNullOrEmpty(userIdString) || !Guid.TryParse(userIdString, out Guid userId))
                {
                    return Unauthorized(new { Message = "Invalid or missing user ID in token." });
                }

                // Create analytics job for background processing
                var inputData = new
                {
                    SessionId = request.SessionId,
                    Title = request.Title
                };

                var jobId = await _jobService.CreateJobAsync("analytics", userId, inputData);

                // Queue background job processing
                await _backgroundTaskQueue.QueueBackgroundWorkItemAsync(async token =>
                {
                    using var scope = HttpContext.RequestServices.CreateScope();
                    var backgroundService = scope.ServiceProvider.GetRequiredService<BackgroundJobService>();
                    await backgroundService.ProcessAnalyticsJobAsync(jobId);
                });

                return Ok(new { JobId = jobId });
            }
            catch (ArgumentException ex)
            {
                return BadRequest(new { Message = ex.Message });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while creating the analytics job.", Details = ex.Message });
            }
        }

        [HttpGet("reports")]
        [Authorize(Roles = $"{SystemRoles.Admin},{SystemRoles.Analyst}")]
        public async Task<IActionResult> GetAnalyticsReports([FromQuery] Guid? sessionId, [FromQuery] int page = 1, [FromQuery] int pageSize = 10)
        {
            try
            {
                var response = await _analyticsService.GetAnalyticsReportsAsync(sessionId, page, pageSize);
                return Ok(response);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while retrieving analytics reports.", Details = ex.Message });
            }
        }

        [HttpGet("reports/{id}")]
        [Authorize(Roles = $"{SystemRoles.Admin},{SystemRoles.Analyst}")]
        public async Task<IActionResult> GetAnalyticsReportById([FromRoute] Guid id)
        {
            try
            {
                var response = await _analyticsService.GetAnalyticsReportByIdAsync(id);
                return Ok(response);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while retrieving the analytics report.", Details = ex.Message });
            }
        }

        [HttpGet("reports/{id}/download")]
        [Authorize(Roles = $"{SystemRoles.Admin},{SystemRoles.Analyst}")]
        public async Task<IActionResult> DownloadAnalyticsReport([FromRoute] Guid id)
        {
            try
            {
                var report = await _analyticsService.GetAnalyticsReportByIdAsync(id);
                
                if (string.IsNullOrEmpty(report.FileUrl))
                {
                    return NotFound(new { Message = "Report file not found" });
                }

                // Download file content from S3 and return as file
                var (fileContent, fileName, contentType) = await _analyticsService.DownloadAnalyticsFileAsync(report.FileUrl);
                
                // Return file directly for download
                return File(fileContent, contentType, fileName);
            }
            catch (FileNotFoundException ex)
            {
                return NotFound(new { Message = ex.Message });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while downloading the analytics report.", Details = ex.Message });
            }
        }
    }
}

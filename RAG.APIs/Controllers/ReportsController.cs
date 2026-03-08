using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RAG.Application.Interfaces;
using RAG.Domain.DTOs.Report;
using RAG.Domain.Enum;
using System.Security.Claims;

namespace RAG.APIs.Controllers
{
    [Route("api/reports")]
    [ApiController]
    public class ReportsController : ControllerBase
    {
        private readonly IReportService _reportService;

        public ReportsController(IReportService reportService)
        {
            _reportService = reportService;
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

                var (filePath, fileName) = await _reportService.DownloadReportAsync(id, internalUserId, roleClaim ?? "");

                if (!System.IO.File.Exists(filePath))
                {
                    return NotFound(new { Message = "The file does not exist on the server." });
                }

                return PhysicalFile(filePath, "application/pdf", fileName);
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
        public async Task<IActionResult> SearchReports([FromQuery] string query, [FromQuery] Guid? companyId, [FromQuery] int? year, [FromQuery] string? period)
        {
            try
            {
                var userIdClaim = User.FindFirst("internal_user_id")?.Value;
                var roleClaim = User.FindFirst(ClaimTypes.Role)?.Value;

                if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out Guid internalUserId))
                {
                    return Unauthorized("User is not authenticated.");
                }

                if (string.IsNullOrWhiteSpace(query))
                {
                    return BadRequest("Query parameter is required.");
                }

                var response = await _reportService.SearchReportsAsync(query, companyId, year, period, internalUserId, roleClaim ?? "");
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

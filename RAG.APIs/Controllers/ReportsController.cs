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
                var userIdClaim = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
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
                var userIdClaim = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
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
                var userIdClaim = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
                var roleClaim = User.FindFirst(ClaimTypes.Role)?.Value;

                if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out Guid internalUserId))
                {
                    return Unauthorized("User is not authenticated.");
                }

                var response = await _reportService.GetReportByIdAsync(id, internalUserId, roleClaim ?? "");
                return Ok(response);
            }
            // 404 Not Found
            catch (KeyNotFoundException ex)
            {
                return NotFound(new { Message = ex.Message });
            }
            // 403 Forbidden
            catch (UnauthorizedAccessException ex)
            {
                return StatusCode(403, new { Message = ex.Message });
            }
            // 500
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while fetching the report.", Details = ex.Message });
            }
        }

    }
}

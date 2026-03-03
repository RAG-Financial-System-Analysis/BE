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

                // In a real application, you might map Cognito Sub -> Internal User Id
                // Assuming NameIdentifier holds the internal Guid Id after claims transformation
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
    }
}

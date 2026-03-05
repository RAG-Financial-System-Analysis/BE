using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RAG.Application.Interfaces.Analaytic;
using RAG.Domain.DTOs.Analytic;
using RAG.Domain.Enum;
using System;
using System.Threading.Tasks;

namespace RAG.APIs.Controllers
{
    [Route("api/analytics")]
    [ApiController]
    public class AnalyticsController : ControllerBase
    {
        private readonly IAnalyticsService _analyticsService;

        public AnalyticsController(IAnalyticsService analyticsService)
        {
            _analyticsService = analyticsService;
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
                var userIdString = User.FindFirst("sub")?.Value ?? User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
                if (string.IsNullOrEmpty(userIdString) || !Guid.TryParse(userIdString, out Guid userId))
                {
                    return Unauthorized(new { Message = "Invalid or missing user ID in token." });
                }

                var response = await _analyticsService.GenerateAnalyticsReportAsync(request, userId);
                return Ok(response);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while generating the analytics report.", Details = ex.Message });
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
    }
}

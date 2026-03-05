using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RAG.Application.Interfaces;
using RAG.Domain.DTOs.Metric;
using RAG.Domain.Enum;
using System;
using System.Threading.Tasks;

namespace RAG.APIs.Controllers
{
    [Route("api/metrics")]
    [ApiController]
    [Authorize(Roles = $"{SystemRoles.Admin},{SystemRoles.Analyst}")]
    public class MetricsController : ControllerBase
    {
        private readonly IMetricService _metricService;

        public MetricsController(IMetricService metricService)
        {
            _metricService = metricService;
        }

        [HttpGet("groups")]
        public async Task<IActionResult> GetMetricGroups()
        {
            try
            {
                var response = await _metricService.GetMetricGroupsAsync();
                return Ok(response);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while retrieving metric groups.", Details = ex.Message });
            }
        }

        [HttpGet("definitions")]
        public async Task<IActionResult> GetMetricDefinitions([FromQuery] Guid? groupId)
        {
            try
            {
                var response = await _metricService.GetMetricDefinitionsAsync(groupId);
                return Ok(response);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while retrieving metric definitions.", Details = ex.Message });
            }
        }

        [HttpGet("values/{reportId}")]
        public async Task<IActionResult> GetMetricValuesByReport([FromRoute] Guid reportId)
        {
            try
            {
                var response = await _metricService.GetMetricValuesByReportAsync(reportId);
                return Ok(response);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while retrieving metric values.", Details = ex.Message });
            }
        }

        [HttpPost("calculate")]
        public async Task<IActionResult> CalculateMetrics([FromBody] CalculateMetricsRequest request)
        {
            try
            {
                var response = await _metricService.CalculateMetricsAsync(request);
                return Ok(response);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while calculating metrics.", Details = ex.Message });
            }
        }
    }
}

using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RAG.Application.Interfaces;
using RAG.Domain.DTOs.Admin;
using RAG.Domain.Enum;
using System;
using System.Threading.Tasks;

namespace RAG.APIs.Controllers
{
    [Route("api/admin")]
    [ApiController]
    [Authorize(Roles = SystemRoles.Admin)]
    public class AdminController : ControllerBase
    {
        private readonly IUserService _userService;
        private readonly IAdminService _adminService;

        public AdminController(IUserService userService, IAdminService adminService)
        {
            _userService = userService;
            _adminService = adminService;
        }

        [HttpGet("users")]
        public async Task<IActionResult> GetAllUsers([FromQuery] int page = 1, [FromQuery] int pageSize = 10, [FromQuery] Guid? roleId = null)
        {
            try
            {
                var response = await _userService.GetAllUsersAsync(page, pageSize, roleId);
                return Ok(response);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while retrieving users.", Details = ex.Message });
            }
        }

        [HttpGet("users/{id}")]
        public async Task<IActionResult> GetUserById([FromRoute] Guid id)
        {
            try
            {
                var response = await _userService.GetUserByIdAsync(id);
                return Ok(response);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while retrieving the user.", Details = ex.Message });
            }
        }

        [HttpPut("users/{id}")]
        public async Task<IActionResult> UpdateUser([FromRoute] Guid id, [FromBody] UpdateUserRequest request)
        {
            try
            {
                await _userService.UpdateUserAsync(id, request);
                return Ok(new { Message = "User updated successfully" });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while updating the user.", Details = ex.Message });
            }
        }

        [HttpDelete("users/{id}")]
        public async Task<IActionResult> DeleteUser([FromRoute] Guid id)
        {
            try
            {
                await _userService.DeleteUserAsync(id);
                return Ok(new { Message = "User deleted successfully" });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while deleting the user.", Details = ex.Message });
            }
        }

        [HttpGet("audit-logs")]
        public async Task<IActionResult> GetAuditLogs(
            [FromQuery] Guid? userId,
            [FromQuery] string? action,
            [FromQuery] DateTime? startDate,
            [FromQuery] DateTime? endDate,
            [FromQuery] int page = 1,
            [FromQuery] int pageSize = 50)
        {
            try
            {
                var response = await _adminService.GetAuditLogsAsync(userId, action ?? string.Empty, startDate, endDate, page, pageSize);
                return Ok(response);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while retrieving audit logs.", Details = ex.Message });
            }
        }

        [HttpGet("statistics")]
        public async Task<IActionResult> GetSystemStatistics()
        {
            try
            {
                var response = await _adminService.GetSystemStatisticsAsync();
                return Ok(response);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while retrieving system statistics.", Details = ex.Message });
            }
        }
        [HttpPost("report-categories")]
        public async Task<IActionResult> CreateReportCategory([FromBody] CreateReportCategoriesRequest request)
        {
            try
            {
                var response = await _adminService.CreateReportCategoryAsync(request);
                return StatusCode(201, response);
            }
            catch (ArgumentException ex)
            {
                return BadRequest(new { Message = ex.Message });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while creating the report category.", Details = ex.Message });
            }
        }

        [HttpGet("report-categories")]
        public async Task<IActionResult> GetReportCategories([FromQuery] int page = 1, [FromQuery] int pageSize = 10)
        {
            try
            {
                var response = await _adminService.GetReportCategoriesAsync(page, pageSize);
                return Ok(response);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while retrieving report categories.", Details = ex.Message });
            }
        }

        [HttpGet("report-categories/{id}")]
        public async Task<IActionResult> GetReportCategoryById([FromRoute] Guid id)
        {
            try
            {
                var response = await _adminService.GetReportCategoryByIdAsync(id);
                return Ok(response);
            }
            catch (KeyNotFoundException ex)
            {
                return NotFound(new { Message = ex.Message });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while retrieving the report category.", Details = ex.Message });
            }
        }

        [HttpPut("report-categories/{id}")]
        public async Task<IActionResult> UpdateReportCategory([FromRoute] Guid id, [FromBody] UpdateReportCategoryRequest request)
        {
            try
            {
                await _adminService.UpdateReportCategoryAsync(id, request);
                return Ok(new { Message = "Report category updated successfully" });
            }
            catch (KeyNotFoundException ex)
            {
                return NotFound(new { Message = ex.Message });
            }
            catch (ArgumentException ex)
            {
                return BadRequest(new { Message = ex.Message });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while updating the report category.", Details = ex.Message });
            }
        }

        [HttpDelete("report-categories/{id}")]
        public async Task<IActionResult> DeleteReportCategory([FromRoute] Guid id)
        {
            try
            {
                await _adminService.DeleteReportCategoryAsync(id);
                return Ok(new { Message = "Report category deleted successfully" });
            }
            catch (KeyNotFoundException ex)
            {
                return NotFound(new { Message = ex.Message });
            }
            catch (InvalidOperationException ex)
            {
                return BadRequest(new { Message = ex.Message });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while deleting the report category.", Details = ex.Message });
            }
        }

        [HttpPost("analytics-types")]
        public async Task<IActionResult> CreateAnalyticsType([FromBody] CreateAnalyticsTypeRequest request)
        {
            try
            {
                var response = await _adminService.CreateAnalyticsTypeAsync(request);
                return StatusCode(201, response);
            }
            catch (ArgumentException ex)
            {
                return BadRequest(new { Message = ex.Message });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while creating the analytics type.", Details = ex.Message });
            }
        }

        [HttpPut("analytics-types/{id}")]
        public async Task<IActionResult> UpdateAnalyticsType([FromRoute] Guid id, [FromBody] UpdateAnalyticsTypeRequest request)
        {
            try
            {
                await _adminService.UpdateAnalyticsTypeAsync(id, request);
                return Ok(new { Message = "Analytics type updated successfully" });
            }
            catch (KeyNotFoundException ex)
            {
                return NotFound(new { Message = ex.Message });
            }
            catch (ArgumentException ex)
            {
                return BadRequest(new { Message = ex.Message });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while updating the analytics type.", Details = ex.Message });
            }
        }

        [HttpDelete("analytics-types/{id}")]
        public async Task<IActionResult> DeleteAnalyticsType([FromRoute] Guid id)
        {
            try
            {
                await _adminService.DeleteAnalyticsTypeAsync(id);
                return Ok(new { Message = "Analytics type deleted successfully" });
            }
            catch (KeyNotFoundException ex)
            {
                return NotFound(new { Message = ex.Message });
            }
            catch (InvalidOperationException ex)
            {
                return BadRequest(new { Message = ex.Message });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while deleting the analytics type.", Details = ex.Message });
            }
        }
    }
}

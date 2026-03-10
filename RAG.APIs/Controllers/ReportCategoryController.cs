using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RAG.Application.Interfaces;
using RAG.Domain.DTOs.Admin;
using System;
using System.Threading.Tasks;

namespace RAG.APIs.Controllers
{
    /// <summary>
    /// Các API công khai (chỉ cần Authenticated) dành cho Analyst và Admin
    /// </summary>
    [Route("api")]
    [ApiController]
    [Authorize]
    public class ReportCategoryController : ControllerBase
    {
        private readonly IAdminService _adminService;

        public ReportCategoryController(IAdminService adminService)
        {
            _adminService = adminService;
        }

        /// <summary>
        /// GET /api/report-categories — Lấy danh sách categories để Analyst dùng khi upload report
        /// </summary>
        [HttpGet("report-categories")]
        public async Task<IActionResult> GetReportCategoriesForAnalyst()
        {
            try
            {
                var response = await _adminService.GetReportCategoriesForAnalystAsync();
                return Ok(response);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while retrieving report categories.", Details = ex.Message });
            }
        }
    }
}

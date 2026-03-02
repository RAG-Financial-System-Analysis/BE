using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RAG.Application.Interfaces;
using RAG.Domain.DTOs.Company;
using RAG.Domain.Enum;
using System;
using System.Threading.Tasks;

namespace RAG.APIs.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class CompaniesController : ControllerBase
    {
        private readonly ICompanyService _companyService;

        public CompaniesController(ICompanyService companyService)
        {
            _companyService = companyService;
        }

        [Authorize(Roles = SystemRoles.Admin + "," + SystemRoles.Analyst)]
        [HttpGet]
        public async Task<IActionResult> GetAll([FromQuery] int page = 1, [FromQuery] int pageSize = 10, [FromQuery] string? industry = null)
        {
            var result = await _companyService.GetAllAsync(page, pageSize, industry);
            return Ok(result);
        }

        [Authorize(Roles = SystemRoles.Admin + "," + SystemRoles.Analyst)]
        [HttpGet("{id}")]
        public async Task<IActionResult> GetById(Guid id)
        {
            var company = await _companyService.GetByIdAsync(id);
            if (company == null) return NotFound();

            return Ok(company);
        }

        [Authorize(Roles = SystemRoles.Admin)]
        [HttpPost]
        public async Task<IActionResult> Create([FromBody] CompanyRequest request)
        {
            try
            {
                var response = await _companyService.CreateAsync(request);
                return CreatedAtAction(nameof(GetById), new { id = response.Id }, new
                {
                    Id = response.Id,
                    Message = "Company created successfully"
                });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Message = ex.Message });
            }
        }

        [Authorize(Roles = SystemRoles.Admin)]
        [HttpPut("{id}")]
        public async Task<IActionResult> Update(Guid id, [FromBody] CompanyRequest request)
        {
            try
            {
                var success = await _companyService.UpdateAsync(id, request);
                if (!success) return NotFound();

                return Ok(new { Message = "Company updated successfully" });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Message = ex.Message });
            }
        }

        [Authorize(Roles = SystemRoles.Admin)]
        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(Guid id)
        {
            try
            {
                var success = await _companyService.DeleteAsync(id);
                if (!success) return NotFound();

                return Ok(new { Message = "Company deleted successfully" });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Message = ex.Message }); // example: company has reports
            }
        }
    }
}

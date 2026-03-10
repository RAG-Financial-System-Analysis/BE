using RAG.Application.Interfaces;
using RAG.Domain;
using RAG.Domain.DTOs.Company;
using System;
using System.Linq;
using System.Threading.Tasks;

namespace RAG.Infrastructure.AWS.Implements
{
    public class CompanyService : ICompanyService
    {
        private readonly ICompanyRepository _companyRepository;

        public CompanyService(ICompanyRepository companyRepository)
        {
            _companyRepository = companyRepository;
        }

        public async Task<CompanyListResponse> GetAllAsync(int page, int pageSize, string? industry)
        {
            var pagedData = await _companyRepository.GetPagedCompaniesAsync(page, pageSize, industry);

            return new CompanyListResponse
            {
                Total = pagedData.TotalItems,
                Page = page,
                PageSize = pageSize,
                Data = pagedData.Companies.Select(c => new CompanyResponse
                {
                    Id = c.Id,
                    Ticker = c.Ticker,
                    Name = c.Name,
                    Industry = c.Industry,
                    Description = c.Description,
                    Website = c.Website,
                    CreatedAt = c.Createdat
                })
            };
        }

        public async Task<CompanyResponse?> GetByIdAsync(Guid id)
        {
            var company = await _companyRepository.GetByIdAsync(id);
            if (company == null) return null;

            return new CompanyResponse
            {
                Id = company.Id,
                Ticker = company.Ticker,
                Name = company.Name,
                Industry = company.Industry,
                Description = company.Description,
                Website = company.Website,
                CreatedAt = company.Createdat
            };
        }

        public async Task<CompanyResponse> CreateAsync(CompanyRequest request)
        {
            var existingCompany = await _companyRepository.FindAsync(c => c.Ticker == request.Ticker);
            if (existingCompany.Any())
            {
                throw new Exception("Ticker already exists");
            }

            var company = new Company
            {
                Id = Guid.NewGuid(),
                Ticker = request.Ticker,
                Name = request.Name,
                Industry = request.Industry,
                Description = request.Description,
                Website = request.Website,
                Createdat = DateTime.SpecifyKind(DateTime.Now, DateTimeKind.Unspecified)
            };

            await _companyRepository.AddAsync(company);

            return new CompanyResponse
            {
                Id = company.Id,
                Ticker = company.Ticker,
                Name = company.Name,
                Industry = company.Industry,
                Description = company.Description,
                Website = company.Website,
                CreatedAt = company.Createdat
            };
        }

        public async Task<bool> UpdateAsync(Guid id, CompanyRequest request)
        {
            var existingCompany = await _companyRepository.GetByIdAsync(id);
            if (existingCompany == null) return false;
            
            // Check Ticker duplicate excluding the current company
            var duplicateTicker = await _companyRepository.FindAsync(c => c.Ticker == request.Ticker && c.Id != id);
            if (duplicateTicker.Any())
            {
                throw new Exception("Ticker already exists");
            }

            existingCompany.Ticker = request.Ticker;
            existingCompany.Name = request.Name;
            existingCompany.Industry = request.Industry;
            existingCompany.Description = request.Description;
            existingCompany.Website = request.Website;
            existingCompany.Updatedat = DateTime.SpecifyKind(DateTime.Now, DateTimeKind.Unspecified);

            _companyRepository.Update(existingCompany);

            return true;
        }

        public async Task<bool> DeleteAsync(Guid id)
        {
            var existingCompany = await _companyRepository.GetByIdAsync(id);
            if (existingCompany == null) return false;

            var hasReports = await _companyRepository.HasReportsAsync(id);
            if (hasReports)
            {
                 throw new Exception("Company has reports (cannot delete)");
            }

            _companyRepository.Delete(existingCompany);

            return true;
        }
    }
}

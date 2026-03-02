using RAG.Domain.DTOs.Company;
using System;
using System.Threading.Tasks;

namespace RAG.Application.Interfaces
{
    public interface ICompanyService
    {
        Task<CompanyListResponse> GetAllAsync(int page, int pageSize, string? industry);
        Task<CompanyResponse?> GetByIdAsync(Guid id);
        Task<CompanyResponse> CreateAsync(CompanyRequest request);
        Task<bool> UpdateAsync(Guid id, CompanyRequest request);
        Task<bool> DeleteAsync(Guid id);
    }
}

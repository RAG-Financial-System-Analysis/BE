using RAG.Domain;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace RAG.Application.Interfaces
{
    public interface ICompanyRepository : IRepository<Company>
    {
        Task<(IEnumerable<Company> Companies, int TotalItems)> GetPagedCompaniesAsync(int page, int pageSize, string? industry);
        Task<bool> HasReportsAsync(Guid companyId);
    }
}

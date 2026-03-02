using Microsoft.EntityFrameworkCore;
using RAG.Application.Interfaces;
using RAG.Domain;
using RAG.Infrastructure.Database;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace RAG.Infrastructure.AWS.Implements
{
    public class CompanyRepository : Repository<Company>, ICompanyRepository
    {
        public CompanyRepository(ApplicationDbContext context) : base(context)
        {
        }

        public async Task<(IEnumerable<Company> Companies, int TotalItems)> GetPagedCompaniesAsync(int page, int pageSize, string? industry)
        {
            var query = _dbSet.AsQueryable();

            if (!string.IsNullOrWhiteSpace(industry))
            {
                query = query.Where(c => c.Industry != null && c.Industry.ToLower() == industry.ToLower());
            }

            int totalItems = await query.CountAsync();

            var pagedData = await query
                .OrderByDescending(c => c.Createdat)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .ToListAsync();

            return (pagedData, totalItems);
        }

        public async Task<bool> HasReportsAsync(Guid companyId)
        {
            return await _context.Set<ReportFinancial>().AnyAsync(r => r.Companyid == companyId);
        }
    }
}

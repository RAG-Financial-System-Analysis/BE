using Microsoft.EntityFrameworkCore;
using RAG.Application.Interfaces;
using RAG.Domain;
using RAG.Infrastructure.Database;
using System;
using System.Collections.Generic;
using System.Text;

namespace RAG.Infrastructure.AWS.Implements
{
    public class RoleRepository : Repository<Role>, IRoleRepository
    {
        public RoleRepository(ApplicationDbContext context) : base(context)
        {
        }

        // Code xử lý lấy từ DB đây:
        public async Task<Role?> GetByNameAsync(string roleName)
        {
            return await _context.Roles
                                       .FirstOrDefaultAsync(r => r.Name.Trim().ToLower() == roleName.Trim().ToLower());
        }
    }
}

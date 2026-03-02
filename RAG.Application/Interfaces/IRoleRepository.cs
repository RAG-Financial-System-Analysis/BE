using RAG.Domain;
using RAG.Infrastructure;
using System;
using System.Collections.Generic;
using System.Text;

namespace RAG.Application.Interfaces
{
    public interface IRoleRepository : IRepository<Role>
    {
        Task<Role?> GetByNameAsync(string roleName);
    }
}

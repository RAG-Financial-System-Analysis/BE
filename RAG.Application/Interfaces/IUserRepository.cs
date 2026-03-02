using RAG.Domain;
using RAG.Infrastructure;
using System;
using System.Collections.Generic;
using System.Text;

namespace RAG.Application.Interfaces
{
    public interface IUserRepository
    {
        Task AddAsync(User user);
        Task<User?> GetByIdAsync(string id);
    }
}

using Microsoft.EntityFrameworkCore;
using RAG.Application.Interfaces;
using RAG.Infrastructure.Database;
using System;
using System.Collections.Generic;
using System.Text;

namespace RAG.Infrastructure.AWS.Implements
{
    public class UserRepository : IUserRepository
    {
        private readonly ApplicationDbContext _context;
        public UserRepository(ApplicationDbContext context) => _context = context;

        public async Task AddAsync(User user)
        {
            await _context.Users.AddAsync(user);
            await _context.SaveChangesAsync();
        }

        public Task<User?> GetByIdAsync(string id)
        {
            throw new NotImplementedException();
        }
    }
}

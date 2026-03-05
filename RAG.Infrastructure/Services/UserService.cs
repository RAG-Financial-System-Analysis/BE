using Microsoft.EntityFrameworkCore;
using RAG.Application.Interfaces;
using RAG.Domain.DTOs.Admin;
using RAG.Infrastructure.Database;
using System;
using System.Linq;
using System.Threading.Tasks;

namespace RAG.Infrastructure.Services
{
    public class UserService : IUserService
    {
        private readonly ApplicationDbContext _dbContext;

        public UserService(ApplicationDbContext dbContext)
        {
            _dbContext = dbContext;
        }

        public async Task<GetUsersResponse> GetAllUsersAsync(int page, int pageSize, Guid? roleId)
        {
            var query = _dbContext.Users.Include(u => u.Role).AsQueryable();

            if (roleId.HasValue)
            {
                query = query.Where(u => u.Roleid == roleId.Value);
            }

            var total = await query.CountAsync();

            var data = await query
                .OrderByDescending(u => u.Createdat)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(u => new UserItemDto
                {
                    Id = u.Id,
                    Email = u.Email,
                    FullName = u.Fullname ?? string.Empty,
                    Role = u.Role != null ? u.Role.Name : string.Empty,
                    IsActive = u.Isactive ?? false,
                    CreatedAt = u.Createdat ?? DateTime.MinValue,
                    LastLoginAt = u.Lastloginat
                })
                .ToListAsync();

            return new GetUsersResponse
            {
                Total = total,
                Page = page,
                PageSize = pageSize,
                Data = data
            };
        }

        public async Task<GetUserByIdResponse> GetUserByIdAsync(Guid id)
        {
            var user = await _dbContext.Users
                .Include(u => u.Role)
                .Include(u => u.ChatSessions)
                .Include(u => u.ReportFinancials)
                .FirstOrDefaultAsync(u => u.Id == id);

            if (user == null)
            {
                throw new Exception("User not found");
            }

            return new GetUserByIdResponse
            {
                Id = user.Id,
                Email = user.Email,
                FullName = user.Fullname ?? string.Empty,
                Role = new RoleDto
                {
                    Id = user.Role != null ? user.Role.Id : Guid.Empty,
                    Name = user.Role != null ? user.Role.Name : string.Empty
                },
                IsActive = user.Isactive ?? false,
                CreatedAt = user.Createdat ?? DateTime.MinValue,
                LastLoginAt = user.Lastloginat,
                Statistics = new UserStatisticsDto
                {
                    ReportsUploaded = user.ReportFinancials.Count,
                    ChatSessions = user.ChatSessions.Count
                }
            };
        }

        public async Task UpdateUserAsync(Guid id, UpdateUserRequest request)
        {
            var user = await _dbContext.Users.FirstOrDefaultAsync(u => u.Id == id);

            if (user == null)
            {
                throw new Exception("User not found");
            }

            user.Fullname = request.FullName;
            user.Roleid = request.RoleId;
            user.Isactive = request.IsActive;

            _dbContext.Users.Update(user);
            await _dbContext.SaveChangesAsync();
        }
    }
}

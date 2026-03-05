using RAG.Domain.DTOs.Admin;
using System;
using System.Threading.Tasks;

namespace RAG.Application.Interfaces
{
    public interface IUserService
    {
        Task<GetUsersResponse> GetAllUsersAsync(int page, int pageSize, Guid? roleId);
        Task<GetUserByIdResponse> GetUserByIdAsync(Guid id);
        Task UpdateUserAsync(Guid id, UpdateUserRequest request);
        Task DeleteUserAsync(Guid id);
    }
}

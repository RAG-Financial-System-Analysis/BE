using RAG.Domain.DTOs.Chat;
using System;
using System.Threading.Tasks;

namespace RAG.Application.Interfaces
{
    public interface IChatService
    {
        Task<CreateChatSessionResponse> CreateSessionAsync(CreateChatSessionRequest request, Guid userId);
        Task<GetChatHistoryResponse> GetChatHistoryAsync(Guid sessionId, Guid userId);
        Task<GetMySessionsResponse> GetMySessionsAsync(Guid userId);
    }
}

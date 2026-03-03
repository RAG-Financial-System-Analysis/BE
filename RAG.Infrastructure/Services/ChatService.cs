using Microsoft.EntityFrameworkCore;
using RAG.Application.Interfaces;
using RAG.Domain;
using RAG.Domain.DTOs.Chat;
using RAG.Infrastructure.Database;
using System;
using System.Threading.Tasks;

namespace RAG.Infrastructure.Services
{
    public class ChatService : IChatService
    {
        private readonly ApplicationDbContext _context;

        public ChatService(ApplicationDbContext context)
        {
            _context = context;
        }

        public async Task<CreateChatSessionResponse> CreateSessionAsync(CreateChatSessionRequest request, Guid userId)
        {
            var typeExists = await _context.AnalyticsTypes.AnyAsync(t => t.Id == request.AnalyticsTypeId);
            if (!typeExists) throw new ArgumentException("Analytics type not found.");

            var newSession = new ChatSession
            {
                Id = Guid.NewGuid(),
                Userid = userId,
                Analyticstypeid = request.AnalyticsTypeId,
                Title = request.Title,
                Starttime = DateTime.Now,
                Createdat = DateTime.Now
            };

            await _context.ChatSessions.AddAsync(newSession);
            await _context.SaveChangesAsync();

            return new CreateChatSessionResponse
            {
                SessionId = newSession.Id,
                Message = "Session created successfully"
            };
        }
    }
}

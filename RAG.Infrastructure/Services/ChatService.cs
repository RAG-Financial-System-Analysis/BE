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

        public async Task<GetChatHistoryResponse> GetChatHistoryAsync(Guid sessionId, Guid userId)
        {
            var sessionExists = await _context.ChatSessions.AnyAsync(s => s.Id == sessionId && s.Userid == userId);
            if (!sessionExists) throw new ArgumentException("Session not found or forbidden");

            var messages = await _context.QuestionPrompts
                .Where(p => p.Sessionid == sessionId)
                .OrderBy(p => p.Createdat)
                .Select(p => new MessageDto
                {
                    Id = p.Id,
                    QuestionText = p.Questiontext,
                    ResponseText = p.Responsetext ?? "",
                    CreatedAt = p.Createdat ?? DateTime.UtcNow
                })
                .ToListAsync();

            return new GetChatHistoryResponse
            {
                SessionId = sessionId,
                Messages = messages
            };
        }

        public async Task<GetMySessionsResponse> GetMySessionsAsync(Guid userId)
        {
            var sessions = await _context.ChatSessions
                .Include(s => s.Analyticstype)
                .Include(s => s.QuestionPrompts)
                .Where(s => s.Userid == userId)
                .OrderByDescending(s => s.Lastmessageat ?? s.Starttime)
                .Select(s => new SessionItemDto
                {
                    Id = s.Id,
                    Title = s.Title,
                    AnalyticsTypeName = s.Analyticstype != null ? s.Analyticstype.Name : "",
                    StartTime = s.Starttime ?? DateTime.UtcNow,
                    LastMessageAt = s.Lastmessageat,
                    MessageCount = s.QuestionPrompts.Count
                })
                .ToListAsync();

            return new GetMySessionsResponse
            {
                Sessions = sessions
            };
        }
    }
}

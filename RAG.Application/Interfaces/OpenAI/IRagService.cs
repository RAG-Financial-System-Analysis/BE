using RAG.Domain.DTOs.OpenAI;
using System;
using System.Collections.Generic;
using System.Text;

namespace RAG.Application.Interfaces.OpenAI
{
    public interface IRagService
    {
        Task<RagResponseDto> AskQuestionAsync(string question, Guid sessionId, Guid userId);
    }
}

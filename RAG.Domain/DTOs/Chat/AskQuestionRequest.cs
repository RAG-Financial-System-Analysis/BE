using System;

namespace RAG.Domain.DTOs.Chat
{
    public class AskQuestionRequest
    {
        public Guid SessionId { get; set; }
        public string QuestionText { get; set; } = null!;
    }
}

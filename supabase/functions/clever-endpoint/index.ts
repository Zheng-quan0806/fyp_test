import { withSupabase } from "npm:@supabase/server@^1";

const tutorInstruction = `
You are Notebook Tutor, a patient tutor who teaches the complete method before
offering the final answer.

Required first-response behavior:
- Explain the learner's exact question, not only a similar example.
- Give every necessary step in one single response.
- Never pause between steps and never require the learner to ask "next step".
- Never tell the learner to calculate an intermediate step without first
  showing how that calculation is set up.
- Use a numbered list in the correct solving order.
- Explain briefly why each step is performed.

For calculations and problem-solving questions:
- Show the values taken from the question.
- Show every substitution, formula, operation, and intermediate calculation.
- Do not skip arithmetic or jump from the question directly to a method.
- Continue through all calculation steps in the same response.
- On the first response, stop only before simplifying or announcing the final
  result. The learner must already have all the working needed to obtain it.
- Do not ask the learner a question in the middle of the steps.

For conceptual questions without a final calculated answer:
- Give the complete explanation in one response.
- Use a short example only when it makes the exact concept clearer.

For questions from images:
- First state what the image is asking.
- Clearly list the readable values or information from the image.
- Then show all required steps for the exact image question in one response.
- If essential information is unreadable, say exactly what is unclear and ask
  for a clearer image. Never invent missing information.

Response formatting:
- Use clean plain text only.
- Do not use Markdown markers such as ** or #.
- Do not use dollar signs as math delimiters or output LaTeX commands.
- Use familiar symbols, readable spacing, short paragraphs, and numbered steps.

Required gentle ending:
- After a calculation or problem-solving explanation, end with exactly:
  "Is this clear? Would you like the final answer, or should I explain the
  steps again in a simpler way?"
- After a conceptual explanation, end with exactly:
  "Is this clear, or should I explain it again in a simpler way?"

Direct-answer exception:
- If the learner asks for the answer, direct answer, full answer, complete
  solution, or equivalent, give the final result and all working immediately.
- Do not withhold an answer when doing so could create a safety risk.
`;

export default {
  fetch: withSupabase({ auth: "publishable" }, async (req) => {
    try {
      if (req.method !== "POST") {
        return Response.json(
          { error: "Only POST requests are allowed." },
          { status: 405 },
        );
      }

      const apiKey = Deno.env.get("GEMINI_API_KEY");
      if (!apiKey) {
        return Response.json(
          { error: "GEMINI_API_KEY is not configured." },
          { status: 500 },
        );
      }

      const body = await req.json();
      const messages = body.messages;
      if (!Array.isArray(messages) || messages.length === 0) {
        return Response.json(
          { error: "A non-empty messages array is required." },
          { status: 400 },
        );
      }

      const contents = messages
        .slice(-20)
        .map((message) => {
          const parts: Array<Record<string, unknown>> = [];
          const text = typeof message?.content === "string"
            ? message.content.trim()
            : "";

          if (text) parts.push({ text });

          const image = message?.image;
          if (
            message?.role !== "assistant" &&
            typeof image?.data === "string" &&
            typeof image?.mimeType === "string" &&
            image.mimeType.startsWith("image/")
          ) {
            if (image.data.length > 8_500_000) {
              throw new Error("The pasted image is too large.");
            }
            parts.push({
              inlineData: {
                mimeType: image.mimeType,
                data: image.data,
              },
            });
          }

          return {
            role: message?.role === "assistant" ? "model" : "user",
            parts,
          };
        })
        .filter((message) => message.parts.length > 0);

      while (contents.length > 0 && contents[0].role === "model") {
        contents.shift();
      }

      if (contents.length === 0) {
        return Response.json(
          { error: "No valid messages were provided." },
          { status: 400 },
        );
      }

      let activeContents = contents;
      const replyChunks: string[] = [];
      let finishReason = "";

      // A detailed tutor response can occasionally reach Gemini's output
      // limit. If that happens, ask Gemini to continue and join both pieces
      // before returning one complete reply to Flutter.
      for (let attempt = 0; attempt < 2; attempt++) {
        const geminiResponse = await fetch(
          "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent",
          {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "x-goog-api-key": apiKey,
            },
            body: JSON.stringify({
              systemInstruction: {
                parts: [{ text: tutorInstruction }],
              },
              contents: activeContents,
              generationConfig: {
                maxOutputTokens: 8192,
                temperature: 0.3,
              },
            }),
          },
        );

        const data = await geminiResponse.json();
        if (!geminiResponse.ok) {
          console.error("Gemini API error:", data);
          return Response.json(
            { error: data?.error?.message ?? "Gemini request failed." },
            { status: 502 },
          );
        }

        const candidate = data?.candidates?.[0];
        const chunk = candidate?.content?.parts
          ?.map((part) => part.text ?? "")
          .join("");
        if (typeof chunk === "string" && chunk.length > 0) {
          replyChunks.push(chunk);
        }

        finishReason = candidate?.finishReason ?? "";
        if (finishReason !== "MAX_TOKENS" || !candidate?.content?.parts) {
          break;
        }

        activeContents = [
          ...activeContents,
          {
            role: "model",
            parts: candidate.content.parts,
          },
          {
            role: "user",
            parts: [{
              text: "Continue exactly where the previous response stopped. " +
                "Do not repeat earlier content. Complete all remaining steps " +
                "and include the required gentle ending.",
            }],
          },
        ];
      }

      const reply = replyChunks.join("").trim();

      if (!reply) {
        return Response.json(
          { error: "Gemini returned an empty response." },
          { status: 502 },
        );
      }

      return Response.json({ reply, finishReason });
    } catch (error) {
      console.error("Notebook Tutor error:", error);
      const message = error instanceof Error
        ? error.message
        : "Unable to process the AI request.";
      return Response.json({ error: message }, { status: 500 });
    }
  }),
};

import QtQuick

/**
 * Anthropic's /v1/messages format.
 *
 * The wire shape is not OpenAI's: the system prompt is its own top-level
 * field, every turn is a list of typed content blocks, and the stream is a
 * sequence of events (`message_start`, `content_block_start`, deltas,
 * `content_block_stop`, `message_delta`, `message_stop`) rather than one
 * shape repeated.
 *
 * Reasoning comes back as `thinking` blocks carrying a signature. The
 * signature is what lets the model pick its own reasoning back up on the next
 * turn, so the blocks are stored on the message and replayed verbatim —
 * editing them invalidates the signature and the turn is rejected.
 */
ApiStrategy {
    readonly property string apiVersion: "2023-06-01"

    // The block currently being streamed. Only one is open at a time.
    property string blockType: ""
    property string toolId: ""
    property string toolName: ""
    property string toolArgs: ""
    property string thinkingText: ""
    property string thinkingSignature: ""
    property int inputTokens: -1
    property int outputTokens: -1

    function buildEndpoint(model: AiModel): string {
        return model.endpoint;
    }

    function buildAuthorizationHeader(apiKeyEnvVarName: string): string {
        return `-H "x-api-key: \$\{${apiKeyEnvVarName}\}" -H "anthropic-version: ${apiVersion}"`;
    }

    /**
     * A message's files as content blocks. Images and PDFs have blocks of
     * their own; anything else the model would only see as bytes goes in as
     * text, which is what source and plain text are worth reading as anyway.
     */
    function attachmentBlocks(message, model: AiModel): var {
        return attachmentsOf(message, model).map(file => {
            if (file.kind === "context") {
                return {
                    "type": "text",
                    "text": String(file.content ?? "")
                };
            }
            if (file.kind === "image") {
                return {
                    "type": "image",
                    "source": {
                        "type": "base64",
                        "media_type": file.mime,
                        "data": attachmentMarker(file.path, "b64")
                    }
                };
            }
            if (file.kind === "pdf") {
                return {
                    "type": "document",
                    "source": {
                        "type": "base64",
                        "media_type": "application/pdf",
                        "data": attachmentMarker(file.path, "b64")
                    }
                };
            }
            return {
                "type": "text",
                "text": `[[ ${file.name} ]]\n${attachmentMarker(file.path, textModeFor(file))}`
            };
        });
    }

    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>) {
        beginAttachments();
        let lastCallId = "";
        const history = [];

        for (let i = 0; i < messages.length; i++) {
            const message = messages[i];
            const hasCall = message.functionName?.length > 0;

            // A tool result belongs to the user turn, as a block pointing back
            // at the call it answers.
            if (hasCall && message.functionResponse?.length > 0) {
                history.push({
                    "role": "user",
                    "content": [
                        lastCallId.length > 0 ? {
                            "type": "tool_result",
                            "tool_use_id": lastCallId,
                            "content": message.functionResponse
                        } : {
                            "type": "text",
                            "text": `[[ Output of ${message.functionName} ]]\n${message.functionResponse}`
                        }
                    ]
                });
                lastCallId = "";
                continue;
            }

            let blocks = [];
            if (message.role === "assistant" && message.thinkingBlocks?.length > 0)
                blocks = blocks.concat(message.thinkingBlocks);
            blocks = blocks.concat(attachmentBlocks(message, model));
            if (message.rawContent?.length > 0)
                blocks.push({
                    "type": "text",
                    "text": message.rawContent
                });
            if (hasCall && message.functionCall?.id) {
                lastCallId = message.functionCall.id;
                blocks.push({
                    "type": "tool_use",
                    "id": message.functionCall.id,
                    "name": message.functionName,
                    "input": message.functionCall.args ?? ({})
                });
            }
            if (blocks.length === 0)
                continue;
            history.push({
                "role": message.role === "assistant" ? "assistant" : "user",
                "content": blocks
            });
        }

        // Anthropic has two incompatible reasoning contracts. Adaptive models
        // use an effort level; older models use a token budget.
        const adaptive = model.thinkingKind === "anthropic-adaptive";
        const budgeted = model.thinkingKind === "anthropic-budget";
        const thinking = thinkingOn(model);
        const budget = thinking ? thinkingBudget(model) : 0;
        let baseData = {
            "model": model.model,
            "system": systemPrompt,
            "messages": history,
            "max_tokens": budgeted && thinking ? Math.max(maxOutputTokens(model), budget + 1024) : maxOutputTokens(model),
            "stream": true
        };
        if (adaptive) {
            baseData.thinking = {
                "type": thinking ? "adaptive" : "disabled"
            };
            if (thinking)
                baseData.output_config = {
                    "effort": thinkingLevel(model)
                };
        } else if (budgeted && thinking) {
            baseData.thinking = {
                "type": "enabled",
                "budget_tokens": budget
            };
        }
        if ((!adaptive || !thinking) && model.samplingParams) {
            // Extended thinking fixes the sampler: a temperature sent next to
            // it is refused, so it is only sent when thinking is off.
            baseData.temperature = temperature;
        }
        if (tools && tools.length > 0)
            baseData.tools = tools;
        return model.extraParams ? Object.assign({}, baseData, model.extraParams) : baseData;
    }

    function parseResponseLine(line, message) {
        const trimmed = line.trim();
        // Event names are on their own line; every one of them repeats the
        // type inside the data payload, so only the payload is read.
        if (!trimmed.startsWith("data:"))
            return {};
        const payload = trimmed.slice(5).trim();
        if (payload.length === 0 || payload === "[DONE]")
            return {};

        try {
            return parseEvent(JSON.parse(payload), message);
        } catch (e) {
            console.log("[AI] Anthropic: Could not parse event: ", e);
        }
        return {};
    }

    function parseEvent(event, message) {
        if (event.type === "error" || event.error) {
            const errorMsg = `**Error**: ${event.error?.message ?? JSON.stringify(event.error ?? event)}`;
            closeThought(message);
            message.rawContent += errorMsg;
            message.content += errorMsg;
            return {
                finished: true
            };
        }

        if (event.type === "content_block_start") {
            blockType = event.content_block?.type ?? "";
            if (blockType === "tool_use") {
                toolId = event.content_block?.id ?? "";
                toolName = event.content_block?.name ?? "";
                toolArgs = "";
            } else if (blockType === "thinking") {
                thinkingText = "";
                thinkingSignature = "";
            }
            return {};
        }

        if (event.type === "content_block_delta") {
            const delta = event.delta ?? {};
            if (delta.type === "thinking_delta") {
                thinkingText += delta.thinking ?? "";
                appendThought(message, delta.thinking ?? "");
            } else if (delta.type === "signature_delta") {
                thinkingSignature += delta.signature ?? "";
            } else if (delta.type === "input_json_delta") {
                toolArgs += delta.partial_json ?? "";
            } else if (delta.type === "text_delta") {
                appendAnswer(message, delta.text ?? "");
            }
            return {};
        }

        if (event.type === "content_block_stop") {
            const type = blockType;
            blockType = "";
            if (type === "thinking" && thinkingText.length > 0) {
                // Kept whole, signature included: this is what gets replayed.
                message.thinkingBlocks = [
                    ...message.thinkingBlocks,
                    {
                        "type": "thinking",
                        "thinking": thinkingText,
                        "signature": thinkingSignature
                    }
                ];
                thinkingText = "";
                thinkingSignature = "";
            }
            if (type === "tool_use" && toolName.length > 0)
                return finishToolCall(message);
            return {};
        }

        if (event.type === "message_delta" || event.type === "message_start") {
            const stopReason = event.delta?.stop_reason ?? event.message?.stop_reason;
            if (stopReason)
                message.finishReason = String(stopReason);
            // The prompt is counted once, at the start; the output count is
            // restated as it grows. Both halves are kept so the later event
            // does not wipe what the earlier one reported.
            const usage = event.usage ?? event.message?.usage;
            if (!usage)
                return {};
            if (usage.input_tokens !== undefined)
                inputTokens = usage.input_tokens;
            if (usage.output_tokens !== undefined)
                outputTokens = usage.output_tokens;
            return {
                tokenUsage: {
                    input: inputTokens,
                    output: outputTokens,
                    total: (inputTokens >= 0 && outputTokens >= 0) ? (inputTokens + outputTokens) : -1
                }
            };
        }

        if (event.type === "message_stop") {
            closeThought(message);
            return {
                finished: true
            };
        }

        return {};
    }

    function finishToolCall(message): var {
        let args = {};
        try {
            args = toolArgs.length > 0 ? JSON.parse(toolArgs) : {};
        } catch (e) {
            console.log("[AI] Anthropic: Could not read call arguments: ", e);
        }
        const name = toolName;
        const id = toolId;
        toolName = "";
        toolId = "";
        toolArgs = "";

        // The call is already a row in the transcript's activity list,
        // with its arguments one click away. Repeating it as a block of
        // JSON inside the answer was a debugging aid that outstayed its
        // welcome.
        closeThought(message);
        message.functionName = name;
        message.functionCall = {
            name: name,
            args: args,
            id: id
        };
        return {
            functionCall: {
                name: name,
                args: args,
                id: id
            }
        };
    }

    function onRequestFinished(message) {
        closeThought(message);
        return {};
    }

    function resetState() {
        blockType = "";
        toolId = "";
        toolName = "";
        toolArgs = "";
        thinkingText = "";
        thinkingSignature = "";
        inputTokens = -1;
        outputTokens = -1;
    }
}

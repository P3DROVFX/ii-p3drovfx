import QtQuick

ApiStrategy {
    readonly property string apiKeyEnvVarName: "API_KEY"
    // Anything the endpoint sends that is not an SSE frame: an error body.
    // Kept until the request ends, because an error body is pretty-printed
    // across many lines.
    property string strayBuffer: ""

    function buildEndpoint(model: AiModel): string {
        // alt=sse makes the stream a sequence of `data: {...}` lines instead
        // of a pretty-printed JSON array, so it is framed like every other
        // provider and no reassembly is needed.
        //
        // The key used to ride in the query string, where the shell never
        // expanded it — the URL reaches curl in single quotes — so Gemini was
        // handed the name of the variable and refused every request. It goes
        // in a header now, the way the other providers send theirs.
        return model.endpoint + "?alt=sse";
    }

    /**
     * The signature Gemini attached to the part it produced. It has to come
     * back untouched on the next turn, or a multi-step answer loses the
     * reasoning it was built on.
     */
    function signaturePart(message): var {
        if (message.role !== "assistant" || !message.thoughtSignature || message.thoughtSignature.length === 0)
            return ({});
        return {
            thoughtSignature: message.thoughtSignature
        };
    }

    /**
     * A message's files as Gemini parts. Text and source go in as themselves;
     * everything else as bytes. `file_data` is still read for chats saved
     * back when attachments were uploaded to the Files API first.
     */
    function attachmentParts(message, model: AiModel): var {
        const parts = attachmentsOf(message, model).map(file => {
            if (file.kind === "context") {
                return {
                    "text": `\n\n${String(file.content ?? "")}`
                };
            }
            if (file.kind === "text") {
                return {
                    "text": `\n\n[[ ${file.name} ]]\n${attachmentMarker(file.path, textModeFor(file))}`
                };
            }
            return {
                "inline_data": {
                    "mime_type": file.mime,
                    "data": attachmentMarker(file.path, "b64")
                }
            };
        });
        if (message.fileUri && message.fileUri.length > 0) {
            parts.push({
                "file_data": {
                    "mime_type": message.fileMimeType,
                    "file_uri": message.fileUri
                }
            });
        }
        return parts;
    }

    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>) {
        beginAttachments();
        const contents = [];
        let lastFunctionResponse = null;
        messages.forEach(message => {
            // console.log("[AI] Building request data for message:", JSON.stringify(message, null, 2));
            const geminiApiRoleName = (message.role === "assistant") ? "model" : message.role;
            const usingSearch = tools?.[0]?.google_search !== undefined;
            const storedCalls = Array.isArray(message.functionCalls) && message.functionCalls.length > 0 ? message.functionCalls : (message.functionCall ? [message.functionCall] : []);
            if (!usingSearch && storedCalls.length > 0 && message.functionName.length > 0) {
                const callParts = storedCalls.map((call, index) => Object.assign({
                    functionCall: {
                        "name": call.name,
                        "args": call.args ?? ({})
                    }
                }, index === 0 ? signaturePart(message) : ({})));
                contents.push({
                    "role": geminiApiRoleName,
                    "parts": callParts
                });
                lastFunctionResponse = null;
                return;
            }
            if (!usingSearch && (message.functionResponse ?? "").length > 0 && message.functionName.length > 0) {
                const responsePart = {
                    functionResponse: {
                        "name": message.functionName,
                        "response": {
                            "content": message.functionResponse
                        }
                    }
                };
                if (!lastFunctionResponse) {
                    lastFunctionResponse = {
                        "role": geminiApiRoleName,
                        "parts": []
                    };
                    contents.push(lastFunctionResponse);
                }
                lastFunctionResponse.parts.push(responsePart);
                return;
            }
            lastFunctionResponse = null;
            contents.push({
                "role": geminiApiRoleName,
                "parts": [
                    Object.assign({
                        text: message.rawContent
                    }, signaturePart(message)),
                    ...attachmentParts(message, model)
                ]
            });
        });
        let baseData = {
            "contents": contents,
            "tools": tools ?? [],
            "system_instruction": {
                "parts": [
                    {
                        text: systemPrompt
                    }
                ]
            },
            "generationConfig": {
                "maxOutputTokens": maxOutputTokens(model)
            }
        };
        // Gemini 3.x asks callers to leave temperature/top_p/top_k out
        // entirely rather than send the defaults, so a model that says it no
        // longer honours them does not get them.
        if (model.samplingParams)
            baseData.generationConfig.temperature = temperature;
        const thinkingConfig = buildThinkingConfig(model);
        if (thinkingConfig)
            baseData.generationConfig.thinkingConfig = thinkingConfig;
        // print("Gemini API call payload:", JSON.stringify(baseData, null, 2));
        return model.extraParams ? Object.assign({}, baseData, model.extraParams) : baseData;
    }

    /**
     * How much reasoning to ask for. The 3.x line takes a named level, the
     * 2.5 line a token budget, and the two are not interchangeable — sending
     * the wrong one is a 400.
     *
     * `includeThoughts` is what makes the summary come back at all; without
     * it the model still reasons, it just never says what it thought.
     */
    function buildThinkingConfig(model: AiModel): var {
        if (!model?.thinking)
            return null;
        const level = thinkingLevel(model);
        if (model.thinkingKind === "gemini-level") {
            return {
                // The 3.x line always reasons; the least it will do is
                // "minimal", which is what "off" means for these models.
                "thinkingLevel": level === "off" ? "minimal" : level,
                "includeThoughts": level !== "off"
            };
        }
        if (model.thinkingKind !== "gemini-budget")
            return null;
        if (level === "off")
            return {
                "thinkingBudget": 0,
                "includeThoughts": false
            };
        return {
            "thinkingBudget": thinkingBudget(model),
            "includeThoughts": true
        };
    }

    function buildAuthorizationHeader(apiKeyEnvVarName: string): string {
        // Gemini has no Authorization header of its own; this is the header
        // form of the `key` parameter. Double quotes, so the shell fills it in.
        return `-H "x-goog-api-key: \$\{${apiKeyEnvVarName}\}"`;
    }

    function parseResponseLine(line, message) {
        const trimmed = line.trim();
        if (trimmed.length === 0)
            return {};

        if (!trimmed.startsWith("data:")) {
            strayBuffer += trimmed;
            return {};
        }

        const payload = trimmed.slice(5).trim();
        if (payload.length === 0)
            return {};
        if (payload === "[DONE]")
            return {
                finished: true
            };

        try {
            return parseData(JSON.parse(payload), message);
        } catch (e) {
            console.log("[AI] Gemini: Could not parse frame: ", e);
            message.rawContent += payload;
            message.content += payload;
        }
        return {};
    }

    function parseData(dataJson, message) {
        let finished = false;
        try {
            // Error response handling
            if (dataJson.error) {
                const errorMsg = `**Error ${dataJson.error.code}**: ${dataJson.error.message}`;
                message.rawContent += errorMsg;
                message.content += errorMsg;
                return {
                    finished: true
                };
            }

            // No candidates?
            if (!dataJson.candidates)
                return {};

            // Finished?
            if (dataJson.candidates[0]?.finishReason) {
                message.finishReason = String(dataJson.candidates[0].finishReason);
                finished = true;
            }

            // Every part, in order. A chunk can hold a thought summary and the
            // start of the answer at once, and reading only the first one
            // drops whichever came second.
            const functionCalls = [];
            const parts = dataJson.candidates[0]?.content?.parts ?? [];
            for (let i = 0; i < parts.length; i++) {
                const part = parts[i];
                if (part.thoughtSignature)
                    message.thoughtSignature = part.thoughtSignature;

                if (part.functionCall) {
                    // The call is already a row in the transcript's activity list,
                    // with its arguments one click away. Repeating it as a block of
                    // JSON inside the answer was a debugging aid that outstayed its
                    // welcome.
                    closeThought(message);
                    message.functionName = part.functionCall.name;
                    const callId = `gemini-${(message.toolCalls?.length ?? message.functionCalls?.length ?? 0) + functionCalls.length + 1}`;
                    const functionCall = {
                        name: part.functionCall.name,
                        args: part.functionCall.args,
                        id: callId
                    };
                    message.functionCall = functionCall;
                    functionCalls.push(functionCall);
                    continue;
                }

                if (!part.text)
                    continue;
                if (part.thought)
                    appendThought(message, part.text);
                else
                    appendAnswer(message, part.text);
            }
            if (functionCalls.length > 0)
                return {
                    functionCalls: functionCalls,
                    finished: finished
                };
            if (finished)
                closeThought(message);

            // Handle annotations and metadata
            const annotationSources = dataJson.candidates[0]?.groundingMetadata?.groundingChunks?.map(chunk => {
                return {
                    "type": "url_citation",
                    "text": chunk?.web?.title,
                    "url": chunk?.web?.uri
                };
            }) ?? [];

            const annotations = dataJson.candidates[0]?.groundingMetadata?.groundingSupports?.map(citation => {
                return {
                    "type": "url_citation",
                    "start_index": citation.segment?.startIndex,
                    "end_index": citation.segment?.endIndex,
                    "text": citation?.segment.text,
                    "url": annotationSources[citation.groundingChunkIndices[0]]?.url,
                    "sources": citation.groundingChunkIndices
                };
            });
            message.annotationSources = annotationSources;
            message.annotations = annotations;
            message.searchQueries = dataJson.candidates[0]?.groundingMetadata?.webSearchQueries ?? [];

            // Usage metadata
            if (dataJson.usageMetadata) {
                return {
                    tokenUsage: {
                        input: dataJson.usageMetadata.promptTokenCount ?? -1,
                        output: dataJson.usageMetadata.candidatesTokenCount ?? -1,
                        thinking: dataJson.usageMetadata.thoughtsTokenCount ?? -1,
                        total: dataJson.usageMetadata.totalTokenCount ?? -1
                    },
                    finished: finished
                };
            }
        } catch (e) {
            console.log("[AI] Gemini: Could not read frame: ", e);
        }
        return {
            finished: finished
        };
    }

    function onRequestFinished(message) {
        closeThought(message);
        if (strayBuffer.length === 0)
            return {};
        const raw = strayBuffer;
        strayBuffer = "";
        try {
            return parseData(JSON.parse(raw), message);
        } catch (e) {
            message.rawContent += raw;
            message.content += raw;
        }
        return {};
    }

    function resetState() {
        strayBuffer = "";
    }

}

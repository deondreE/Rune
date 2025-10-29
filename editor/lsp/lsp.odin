package lsp

import "core:encoding/json"

ResponseError :: struct {
    code: json.Integer,
    message: json.String,
    data: json.Object,
}

Message :: struct {
    version: json.String,
    id: json.Object,
    method: json.String,
    params: json.Array,
    result: json.Object,
    error: ^ResponseError,
}

ClientInfo :: struct {
    name: json.String,
    version: json.String,
}

WorkspaceCapabilities :: struct {
    applyEdit: json.Boolean,
    workspaceEdit: ^WorkspaceEditCapabilities,
    didChangeConfiguration: ^DidChangeConfigurationClientCapabilities,
    didChangeWatchedFiles: ^DidChangeWatchedFilesClientCapabilities,
    symbol: ^WorkspaceSymbolClientCapabilities,
    executeCommand: ^ExecuteCommandClientCapabilities,
    semanticTokens: ^SemanticTokensClientCapabilities,
    configuration: ^ConfigurationClientCapabilities,
    inlineValue: ^InlineValueClientCapabilities,
    codeLens: ^CodeLensClientCapabilities,
    callHierachy: ^CallHierarchyClientCapabilities,
    foldingRange: ^FoldingRangeClientCapabilities,
    typeHierarchy: ^TypeHierarchyClientCapabilities,
    linkedEditingRange: ^LinkedEditingRangeClientCapabilities,
    Monaco: json.Object,
}

ChangeAnnotationSupportCapabilities :: struct {
    groups: json.Boolean,
} 

DidChangeConfigurationCapabilities :: struct {
    dynamicRegistration: json.Boolean,
}

WorkspaceEditCapabilities :: struct {
    normalizationEdit: json.Boolean,
    insertEdit: json.Boolean,
    chagneAnnotationSupport: ^ChangeAnnotationSupportCapabilities,
}

Capabilities :: struct {
    workspace: ^WorkspaceCapabilties,
    textDocument: ^TextDocumentCapabilities,
    expirimental: json.Object,
}

InitParams :: struct {
    clientInfo: ^ClientInfo,
    capablilities: Capabilities,
    workspaceFolders: []WorkspaceFolder,
    clientCapabilities: Capabilities,
    processID: json.Integer,
    initializationOptions: json.Object,
}
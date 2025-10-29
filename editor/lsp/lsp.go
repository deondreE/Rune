/*package main

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/rpc"
	"net/rpc/jsonrpc"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"sync"
	"time"
)

// ----- JSON-RPC Message Structures -----

// Message represents a JSON-RPC 2.0 message.
type Message struct {
	Version string           `json:"jsonrpc"`
	ID      interface{}      `json:"id,omitempty"`
	Method  string           `json:"method,omitempty"`
	Params  *json.RawMessage `json:"params,omitempty"`
	Result  interface{}      `json:"result,omitempty"`
	Error   *ResponseError   `json:"error,omitempty"`
}

// ResponseError represents a JSON-RPC error object.
type ResponseError struct {
	Code    int         `json:"code"`
	Message string      `json:"message"`
	Data    interface{} `json:"data,omitempty"`
}

// ----- LSP Initialization Structures -----

// InitializeParams contains parameters for the 'initialize' request.
type InitializeParams struct {
	ClientInfo *ClientInfo `json:"clientInfo,omitempty"`
	Capabilities Capabilities `json:"capabilities"`
	// RootPath string `json:"rootPath,omitempty"` // Deprecated
	// RootURI string `json:"rootUri,omitempty"` // Deprecated
	WorkspaceFolders []WorkspaceFolder `json:"workspaceFolders,omitempty"`
	// ClientCapabilities is an alias for Capabilities
	ClientCapabilities Capabilities `json:"clientCapabilities"`
	// ProcessId is the process ID of the parent process that started the server.
	ProcessId int `json:"processId,omitempty"`
	// InitializationOptions could be anything.
	InitializationOptions interface{} `json:"initializationOptions,omitempty"`
}

// ClientInfo contains information about the client (editor).
type ClientInfo struct {
	Name    string `json:"name"`
	Version string `json:"version"`
}

// Capabilities represents the capabilities of the client or server.
type Capabilities struct {
	Workspace    *WorkspaceCapabilities    `json:"workspace,omitempty"`
	TextDocument *TextDocumentCapabilities `json:"textDocument,omitempty"`
	Experimental interface{} `json:"experimental,omitempty"`
}

// WorkspaceCapabilities represents workspace specific capabilities.
type WorkspaceCapabilities struct {
	ApplyEdit               *bool                      `json:"applyEdit,omitempty"`
	WorkspaceEdit           *WorkspaceEditCapabilities `json:"workspaceEdit,omitempty"`
	DidChangeConfiguration  *DidChangeConfigurationClientCapabilities `json:"didChangeConfiguration,omitempty"`
	DidChangeWatchedFiles   *DidChangeWatchedFilesClientCapabilities `json:"didChangeWatchedFiles,omitempty"`
	Symbol                  *WorkspaceSymbolClientCapabilities `json:"symbol,omitempty"`
	ExecuteCommand          *ExecuteCommandClientCapabilities `json:"executeCommand,omitempty"`
	// SemanticTokens are capabilities related to semantic tokens.
	SemanticTokens *SemanticTokensClientCapabilities `json:"semanticTokens,omitempty"`
	// Configuration: Capabilities around configuration requests.
	Configuration *ConfigurationClientCapabilities `json:"configuration,omitempty"`
	// InlineValue: Capabilities related to inline values.
	InlineValue *InlineValueClientCapabilities `json:"inlineValue,omitempty"`
	// CodeLens: Capabilities related to code lens.
	CodeLens *CodeLensClientCapabilities `json:"codeLens,omitempty"`
	// CallHierarchy: Capabilities related to call hierarchy.
	CallHierarchy *CallHierarchyClientCapabilities `json:"callHierarchy,omitempty"`
	// FoldingRange: Capabilities related to folding ranges.
	FoldingRange *FoldingRangeClientCapabilities `json:"foldingRange,omitempty"`
	// TypeHierarchy: Capabilities related to type hierarchy.
	TypeHierarchy *TypeHierarchyClientCapabilities `json:"typeHierarchy,omitempty"`
	// LinkedEditingRange: Capabilities related to linked editing ranges.
	LinkedEditingRange *LinkedEditingRangeClientCapabilities `json:"linkedEditingRange,omitempty"`
	// Monaco: Capabilities specific to Monaco editor.
	Monaco interface{} `json:"monaco,omitempty"`
	// ... other workspace capabilities
}

// WorkspaceEditCapabilities represents capabilities for workspace edits.
type WorkspaceEditCapabilities struct {
	// NormalizationEdit is true if the client supports normalize-edit.
	NormalizationEdit bool `json:"normalizeEdit,omitempty"`
	// InsertEdit is true if the client supports insert-edit.
	InsertEdit bool `json:"insertEdit,omitempty"`
	// ChangeAnnotationSupport is the client's support for change annotations.
	ChangeAnnotationSupport *ChangeAnnotationSupportCapabilities `json:"changeAnnotationSupport,omitempty"`
}

// ChangeAnnotationSupportCapabilities represents the client's support for change annotations.
type ChangeAnnotationSupportCapabilities struct {
	Groups bool `json:"groups,omitempty"`
}

// DidChangeConfigurationClientCapabilities represents client capabilities for didChangeConfiguration.
type DidChangeConfigurationClientCapabilities struct {
	DynamicRegistration bool `json:"dynamicRegistration,omitempty"`
}

// DidChangeWatchedFilesClientCapabilities represents client capabilities for didChangeWatchedFiles.
type DidChangeWatchedFilesClientCapabilities struct {
	DynamicRegistration bool `json:"dynamicRegistration,omitempty"`
	// These are optional, and should be empty if not supported.
	// See https://microsoft.github.io/language-server-protocol/specifications/specification-current/#watchkind
	WatchKind *string `json:"watchKind,omitempty"`
}

// WorkspaceSymbolClientCapabilities represents client capabilities for workspace symbols.
type WorkspaceSymbolClientCapabilities struct {
	// SymbolKind defines the capabilities for symbol kinds.
	SymbolKind *SymbolKindCapabilities `json:"symbolKind,omitempty"`
	// SearchProvider indicates whether the client supports searching for workspace symbols.
	SearchProvider bool `json:"searchProvider,omitempty"`
}

// SymbolKindCapabilities defines the capabilities for symbol kinds.
type SymbolKindCapabilities struct {
	ValueSet []int `json:"valueSet,omitempty"`
}

// ExecuteCommandClientCapabilities represents client capabilities for executeCommand.
type ExecuteCommandClientCapabilities struct {
	// Commands is the list of commands supported by the client.
	Commands []string `json:"commands,omitempty"`
	// ArgumentValidation is true if the client supports argument validation.
	ArgumentValidation bool `json:"argumentValidation,omitempty"`
}

// SemanticTokensClientCapabilities represents client capabilities for semantic tokens.
type SemanticTokensClientCapabilities struct {
	DynamicRegistration bool `json:"dynamicRegistration,omitempty"`
	// Full indicates support for full semantic token requests.
	Full *SemanticTokensOptions `json:"full,omitempty"`
	// Range indicates support for range-based semantic token requests.
	Range *SemanticTokensOptions `json:"range,omitempty"`
	// Types is the list of token types supported by the client.
	Types []string `json:"types,omitempty"`
	// Edits supports edits for semantic tokens.
	Edits bool `json:"edits,omitempty"`
}

// SemanticTokensOptions represents options for semantic tokens.
type SemanticTokensOptions struct {
	// Full is true if the client supports full requests.
	Full bool `json:"full,omitempty"`
	// Range is true if the client supports range requests.
	Range bool `json:"range,omitempty"`
}

// ConfigurationClientCapabilities represents client capabilities for configuration.
type ConfigurationClientCapabilities struct {
	// DynamicRegistration is true if the client supports dynamic registration for configuration.
	DynamicRegistration bool `json:"dynamicRegistration,omitempty"`
}

// InlineValueClientCapabilities represents client capabilities for inline values.
type InlineValueClientCapabilities struct {
	// DynamicRegistration is true if the client supports dynamic registration for inline values.
	DynamicRegistration bool `json:"dynamicRegistration,omitempty"`
}

// CodeLensClientCapabilities represents client capabilities for code lenses.
type CodeLensClientCapabilities struct {
	// DynamicRegistration is true if the client supports dynamic registration for code lenses.
	DynamicRegistration bool `json:"dynamicRegistration,omitempty"`
}

// CallHierarchyClientCapabilities represents client capabilities for call hierarchy.
type CallHierarchyClientCapabilities struct {
	// DynamicRegistration is true if the client supports dynamic registration for call hierarchy.
	DynamicRegistration bool `json:"dynamicRegistration,omitempty"`
}

// FoldingRangeClientCapabilities represents client capabilities for folding ranges.
type FoldingRangeClientCapabilities struct {
	// DynamicRegistration is true if the client supports dynamic registration for folding ranges.
	DynamicRegistration bool `json:"dynamicRegistration,omitempty"`
	// LineFoldingOnly: Indicates that the client only supports folding ranges that are defined by lines.
	LineFoldingOnly bool `json:"lineFoldingOnly,omitempty"`
	// FoldingRangeKind: The kind of folding ranges the client supports.
	FoldingRangeKind *FoldingRangeKindCapabilities `json:"foldingRangeKind,omitempty"`
	// RangeLimit: The maximum number of folding ranges supported.
	RangeLimit *int `json:"rangeLimit,omitempty"`
}

// FoldingRangeKindCapabilities represents the kind of folding ranges the client supports.
type FoldingRangeKindCapabilities struct {
	ValueSets []string `json:"valueSet,omitempty"`
}

// TypeHierarchyClientCapabilities represents client capabilities for type hierarchy.
type TypeHierarchyClientCapabilities struct {
	// DynamicRegistration is true if the client supports dynamic registration for type hierarchy.
	DynamicRegistration bool `json:"dynamicRegistration,omitempty"`
}

// LinkedEditingRangeClientCapabilities represents client capabilities for linked editing ranges.
type LinkedEditingRangeClientCapabilities struct {
	// DynamicRegistration is true if the client supports dynamic registration for linked editing ranges.
	DynamicRegistration bool `json:"dynamicRegistration,omitempty"`
}

// TextDocumentCapabilities represents text document specific capabilities.
type TextDocumentCapabilities struct {
	Synchronization      *TextDocumentSyncCapabilities      `json:"synchronization,omitempty"`
	Completion           *CompletionTextDocumentCapabilities `json:"completion,omitempty"`
	Hover                *HoverTextDocumentCapabilities      `json:"hover,omitempty"`
	SignatureHelp        *SignatureHelpTextDocumentCapabilities `json:"signatureHelp,omitempty"`
	Declaration          *DeclarationTextDocumentCapabilities `json:"declaration,omitempty"`
	Definition           *DefinitionTextDocumentCapabilities `json:"definition,omitempty"`
	TypeDefinition       *TypeDefinitionTextDocumentCapabilities `json:"typeDefinition,omitempty"`
	Implementation       *ImplementationTextDocumentCapabilities `json:"implementation,omitempty"`
	References           *ReferenceTextDocumentCapabilities `json:"references,omitempty"`
	DocumentHighlight    *DocumentHighlightTextDocumentCapabilities `json:"documentHighlight,omitempty"`
	DocumentSymbol       *DocumentSymbolTextDocumentCapabilities `json:"documentSymbol,omitempty"`
	CodeAction           *CodeActionTextDocumentCapabilities `json:"codeAction,omitempty"`
	CodeLens             *CodeLensTextDocumentCapabilities `json:"codeLens,omitempty"`
	Formatting           *DocumentFormattingClientCapabilities `json:"formatting,omitempty"`
	RangeFormatting      *DocumentRangeFormattingClientCapabilities `json:"rangeFormatting,omitempty"`
	Rename               *RenameTextDocumentCapabilities `json:"rename,omitempty"`
	PublishDiagnostics   *PublishDiagnosticsClientCapabilities `json:"publishDiagnostics,omitempty"`
	// SemanticTokens represents text document specific capabilities for semantic tokens.
	SemanticTokens *SemanticTokensTextDocumentClientCapabilities `json:"semanticTokens,omitempty"`
	// DocumentLink: Capabilities for document links.
	DocumentLink *DocumentLinkClientCapabilities `json:"documentLink,omitempty"`
	// InlineValue: Capabilities for inline values.
	InlineValue *InlineValueTextDocumentClientCapabilities `json:"inlineValue,omitempty"`
	// CallHierarchy: Capabilities for call hierarchy.
	CallHierarchy *CallHierarchyTextDocumentClientCapabilities `json:"callHierarchy,omitempty"`
	// FoldingRange: Capabilities for folding ranges.
	FoldingRange *FoldingRangeTextDocumentClientCapabilities `json:"foldingRange,omitempty"`
	// TypeHierarchy: Capabilities for type hierarchy.
	TypeHierarchy *TypeHierarchyTextDocumentClientCapabilities `json:"typeHierarchy,omitempty"`
	// LinkedEditingRange: Capabilities for linked editing ranges.
	LinkedEditingRange *LinkedEditingRangeTextDocumentClientCapabilities `json:"linkedEditingRange,omitempty"`
	// Monaco: Capabilities specific to Monaco editor.
	Monaco interface{} `json:"monaco,omitempty"`
	// ... other text document capabilities
}

// TextDocumentSyncCapabilities represents synchronization capabilities for text documents.
type TextDocumentSyncCapabilities struct {
	// SyncKind: The way the text document is synchronized.
	SyncKind int `json:"syncKind"` // 0: None, 1: Full, 2: Incremental
	// Options: Options specific to the chosen sync kind.
	Options interface{} `json:"options,omitempty"`
	// Change: Represents the capability to send changes.
	Change *string `json:"change,omitempty"`
}

// Synchronization Options for incremental sync.
type TextDocumentSyncOptions struct {
	OpenClose         bool `json:"openClose"`
	Change            int  `json:"change"` // 1: Full, 2: Incremental
	WillSave          bool `json:"willSave"`
	WillSaveWaitUntil bool `json:"willSaveWaitUntil"`
	DidSave           bool `json:"didSave"`
}

// CompletionTextDocumentCapabilities represents client capabilities for completion.
type CompletionTextDocumentCapabilities struct {
	DynamicRegistration bool `json:"dynamicRegistration,omitempty"`
	// CompletionItem: Capabilities related to completion items.
	CompletionItem *CompletionItemCapabilities `json:"completionItem,omitempty"`
	// Context: Capabilities related to completion context.
	Context *CompletionContextCapabilities `json:"context,omitempty"`
	// CompletionItemKind: Capabilities related to completion item kinds.
	CompletionItemKind *CompletionItemKindCapabilities `json:"completionItemKind,omitempty"`
	// InsertTextFormat: The format of the insert text.
	InsertTextFormat int `json:"insertTextFormat,omitempty"`
	// ResolveProvider: Whether the client supports resolving additional details for completion items.
	ResolveProvider bool `json:"resolveProvider,omitempty"`
	// SupportedSortOrders: The sort orders supported by the client.
	SupportedSortOrders []string `json:"supportedSortOrders,omitempty"`
}

// CompletionItemCapabilities represents capabilities related to completion items.
type CompletionItemCapabilities struct {
	// DocumentationFormat: The documentation format supported by the client.
	DocumentationFormat []string `json:"documentationFormat,omitempty"`
	// CommitCharacters: The commit characters supported by the client.
	CommitCharacters []string `json:"commitCharacters,omitempty"`
	// PreselectSupport: Whether the client supports preselecting completion items.
	PreselectSupport bool `json:"preselectSupport,omitempty"`
	// InsertReplaceSupport: Whether the client supports insert and replace modes for completion items.
	InsertReplaceSupport bool `json:"insertReplaceSupport,omitempty"`
	// InsertTextMode: The insert text mode.
	InsertTextMode int `json:"insertTextMode,omitempty"`
	// LabelDetailsSupport: Whether the client supports label details.
	LabelDetailsSupport bool `json:"labelDetailsSupport,omitempty"`
	}

// CompletionContextCapabilities represents capabilities related to completion context.
type CompletionContextCapabilities struct {
	TypeSupport bool `json:"typeSupport,omitempty"`
}

// CompletionItemKindCapabilities represents capabilities related to completion item kinds.
type CompletionItemKindCapabilities struct {
	// ValueSet: The set of completion item kinds supported by the client.
	ValueSet []int `json:"valueSet,omitempty"`
}

// HoverTextDocumentCapabilities represents client capabilities for hover.
type HoverTextDocumentCapabilities struct {
	DynamicRegistration bool `json:"dynamicRegistration,omitempty"`
	ContentFormat []string `json:"contentFormat,omitempty"`
}

// SignatureHelpTextDocumentCapabilities represents client capabilities for signature help.
type SignatureHelpTextDocumentCapabilities struct {
	DynamicRegistration bool `json:"dynamicRegistration,omitempty"`
	// SignatureInformation: Capabilities related to signature information.
	SignatureInformation *SignatureInformationCapabilities `json:"signatureInformation,omitempty"`
	// Context: Capabilities related to signature help context.
	Context *SignatureHelpContextCapabilities `json:"context,omitempty"`
}

// SignatureInformationCapabilities represents capabilities related to signature information.
type SignatureInformationCapabilities struct {
	// DocumentationFormat: The documentation format supported by the client.
	DocumentationFormat []string `json:"documentationFormat,omitempty"`
	// ParameterInformation: Capabilities related to parameter information.
	ParameterInformation *ParameterInformationCapabilities `json:"parameterInformation,omitempty"`
	// ActiveParameterSupport: Whether the client supports active parameter.
	ActiveParameterSupport bool `json:"activeParameterSupport,omitempty"`
}

// ParameterInformationCapabilities represents capabilities related to parameter information.
type ParameterInformationCapabilities struct {
	// LabelOffsetSupport: Whether the client supports label offsets.
	LabelOffsetSupport bool `json:"labelOffsetSupport,omitempty"`
}

// SignatureHelpContextCapabilities represents capabilities related to signature help context.
type SignatureHelpContextCapabilities struct {
	// TypeSupport: Whether the client supports type support.
	TypeSupport bool `json:"typeSupport,omitempty"`
}

// DeclarationTextDocumentCapabilities represents client capabilities for declaration.
type DeclarationTextDocumentCapabilities struct {
	// DynamicRegistration: Whether the client supports dynamic registration.
	DynamicRegistration bool `json:"dynamicRegistration,omitempty"`
	// LinkSupport: Whether the client supports linking to declarations.
	LinkSupport bool `json:"linkSupport,omitempty"`
}

// DefinitionTextDocumentCapabilities represents client capabilities for definition.
type DefinitionTextDocumentCapabilities struct {
	DynamicRegistration bool `json:"dynamicRegistration,omitempty"`
	// LinkSupport: Whether the client supports linking to definitions.
	LinkSupport bool `json:"linkSupport,omitempty"`
}

// TypeDefinitionTextDocumentCapabilities represents client capabilities for type definition.
type TypeDefinitionTextDocumentCapabilities struct {
	DynamicRegistration bool `json:"dynamicRegistration,omitempty"`
	// LinkSupport: Whether the client supports linking to type definitions.
	LinkSupport bool `json:"linkSupport,omitempty"`
}

// ImplementationTextDocumentCapabilities represents client capabilities for implementation.
type ImplementationTextDocumentCapabilities struct {
	DynamicRegistration bool `json:"dynamicRegistration,omitempty"`
	// LinkSupport: Whether the client supports linking to implementations.
	LinkSupport bool `json:"linkSupport,omitempty"`
}

// ReferenceTextDocumentCapabilities represents client capabilities for references.
type ReferenceTextDocumentCapabilities struct {
	DynamicRegistration bool `json:"dynamicRegistration,omitempty"`
	// Generic: Whether the client supports generic references.
	Generic bool `json:"generic,omitempty"`
	// IgnoreUnregistered: Whether the client ignores unregistered references.
	IgnoreUnregistered bool `json:"ignoreUnregistered,omitempty"`
}

// DocumentHighlightTextDocumentCapabilities represents client capabilities for document highlights.
type DocumentHighlightTextDocumentCapabilities struct {
	DynamicRegistration bool `json:"dynamicRegistration,omitempty"`
}

// DocumentSymbolTextDocumentCapabilities represents client capabilities for document symbols.
type DocumentSymbolTextDocumentCapabilities struct {
	DynamicRegistration bool `json:"dynamicRegistration,omitempty"`
	// SymbolKind: Capabilities related to symbol kinds.
	SymbolKind *SymbolKindCapabilities `json:"symbolKind,omitempty"`
	// HierarchicalDocumentSymbolSupport: Whether the client supports hierarchical document symbols.
	HierarchicalDocumentSymbolSupport bool `json:"hierarchicalDocumentSymbolSupport,omitempty"`
}

// CodeActionTextDocumentCapabilities represents client capabilities for code actions.
type CodeActionTextDocumentCapabilities struct {
	DynamicRegistration bool `json:"dynamicRegistration,omitempty"`
	// CodeActionLiteralSupport: The literal support for code actions.
	CodeActionLiteralSupport *CodeActionLiteralSupportCapabilities `json:"codeActionLiteralSupport,omitempty"`
	// IsPreferredSupport: Whether the client supports preferred code actions.
	IsPreferredSupport bool `json:"isPreferredSupport,omitempty"`
	//disabledSupport: Whether the client supports disabling code actions.
	DisabledSupport bool `json:"disabledSupport,omitempty"`
	// DataProviderSupport: Whether the client supports data providers for code actions.
	DataProviderSupport bool `json:"dataProviderSupport,omitempty"`
	// KindReport: Whether the client supports reporting kinds for code actions.
	KindReport bool `json:"kindReport,omitempty"`
}

// CodeActionLiteralSupportCapabilities represents the literal support for code actions.
type CodeActionLiteralSupportCapabilities struct {
	CodeActionKind *CodeActionKindCapabilities `json:"codeActionKind,omitempty"`
}

// CodeActionKindCapabilities represents the kinds of code actions supported by the client.
type CodeActionKindCapabilities struct {
	ValueSets []string `json:"valueSet,omitempty"`
}

// CodeLensTextDocumentCapabilities represents client capabilities for code lenses.
type CodeLensTextDocumentCapabilities struct {
	DynamicRegistration bool `json:"dynamicRegistration,omitempty"`
}

// DocumentFormattingClientCapabilities represents client capabilities for document formatting.
type DocumentFormattingClientCapabilities struct {
	DynamicRegistration bool `json:"dynamicRegistration,omitempty"`
}

// DocumentRangeFormattingClientCapabilities represents client capabilities for document range formatting.
type DocumentRangeFormattingClientCapabilities struct {
	DynamicRegistration bool `json:"dynamicRegistration,omitempty"`
}

// RenameTextDocumentCapabilities represents client capabilities for rename.
type RenameTextDocumentCapabilities struct {
	DynamicRegistration bool `json:"dynamicRegistration,omitempty"`
	// PrepareSupport: Whether the client supports prepare support for renames.
	PrepareSupport bool `json:"prepareSupport,omitempty"`
	// HighlightSupport: Whether the client supports highlighting during rename.
	HighlightSupport bool `json:"highlightSupport,omitempty"`
	// Options: Options for rename.
	Options interface{} `json:"options,omitempty"`
}

// PublishDiagnosticsClientCapabilities represents client capabilities for publishing diagnostics.
type PublishDiagnosticsClientCapabilities struct {
	// RelatedInformation: Whether the client supports related information for diagnostics.
	RelatedInformation bool `json:"relatedInformation,omitempty"`
	// TagSupport: Capabilities related to diagnostic tags.
	TagSupport *DiagnosticTagSupportCapabilities `json:"tagSupport,omitempty"`
	// VersionSupport: Whether the client supports versioned diagnostics.
	VersionSupport bool `json:"versionSupport,omitempty"`
	// CodeActions: Whether the client supports code actions for diagnostics.
	CodeActions bool `json:"codeActions,omitempty"`
}

// DiagnosticTagSupportCapabilities represents capabilities for diagnostic tags.
type DiagnosticTagSupportCapabilities struct {
	ValueSets []string `json:"valueSet,omitempty"`
}

// SemanticTokensTextDocumentClientCapabilities represents text document specific capabilities for semantic tokens.
type SemanticTokensTextDocumentClientCapabilities struct {
	DynamicRegistration bool `json:"dynamicRegistration,omitempty"`
	// Full: Capabilities for full semantic token requests.
	Full *SemanticTokensCapabilities `json:"full,omitempty"`
	// Range: Capabilities for range-based semantic token requests.
	Range *SemanticTokensCapabilities `json:"range,omitempty"`
	// Types: The token types supported by the client.
	Types []string `json:"types,omitempty"`
	// Edits: Whether the client supports edits for semantic tokens.
	Edits bool `json:"edits,omitempty"`
}

// DocumentLinkClientCapabilities represents client capabilities for document links.
type DocumentLinkClientCapabilities struct {
	DynamicRegistration bool `json:"dynamicRegistration,omitempty"`
	// Tooltip: Whether the client supports tooltips for document links.
	Tooltip bool `json:"tooltip,omitempty"`
}

// InlineValueTextDocumentClientCapabilities represents text document specific capabilities for inline values.
type InlineValueTextDocumentClientCapabilities struct {
	DynamicRegistration bool `json:"dynamicRegistration,omitempty"`
}

// CallHierarchyTextDocumentClientCapabilities represents text document specific capabilities for call hierarchy.
type CallHierarchyTextDocumentClientCapabilities struct {
	DynamicRegistration bool `json:"dynamicRegistration,omitempty"`
}

// FoldingRangeTextDocumentClientCapabilities represents text document specific capabilities for folding ranges.
type FoldingRangeTextDocumentClientCapabilities struct {
	DynamicRegistration bool `json:"dynamicRegistration,omitempty"`
	// LineFoldingOnly: Indicates that the client only supports folding ranges that are defined by lines.
	LineFoldingOnly bool `json:"lineFoldingOnly,omitempty"`
	// FoldingRangeKind: The kind of folding ranges the client supports.
	FoldingRangeKind *FoldingRangeKindCapabilities `json:"foldingRangeKind,omitempty"`
	// RangeLimit: The maximum number of folding ranges supported.
	RangeLimit *int `json:"rangeLimit,omitempty"`
}

// TypeHierarchyTextDocumentClientCapabilities represents text document specific capabilities for type hierarchy.
type TypeHierarchyTextDocumentClientCapabilities struct {
	DynamicRegistration bool `json:"dynamicRegistration,omitempty"`
}

// LinkedEditingRangeTextDocumentClientCapabilities represents text document specific capabilities for linked editing ranges.
type LinkedEditingRangeTextDocumentClientCapabilities struct {
	DynamicRegistration bool `json:"dynamicRegistration,omitempty"`
}

// WorkspaceFolder represents a folder in the workspace.
type WorkspaceFolder struct {
	URI  string `json:"uri"`
	Name string `json:"name"`
}

// InitializeResult contains the server's capabilities in response to an initialize request.
type InitializeResult struct {
	Capabilities ServerCapabilities `json:"capabilities"`
	ServerInfo   *ServerInfo `json:"serverInfo,omitempty"`
}

// ServerInfo contains information about the server.
type ServerInfo struct {
	Name string `json:"name"`
	// Version is the server's version.
	Version string `json:"version,omitempty"`
	// BuildInfo is optional build information.
	BuildInfo []string `json:"buildInfo,omitempty"`
}

// ServerCapabilities defines the capabilities the language server provides.
type ServerCapabilities struct {
	// TextDocumentSync: Defines how the text document is synchronized.
	// 0: None, 1: Full, 2: Incremental
	TextDocumentSync int `json:"textDocumentSync,omitempty"`
	// Spellcheck: Whether the server provides spell checking.
	Spellcheck bool `json:"spellcheck,omitempty"`
	// CompletionProvider: Defines capabilities for completion requests.
	CompletionProvider *CompletionOptions `json:"completionProvider,omitempty"`
	// HoverProvider: Whether the server provides hover information.
	HoverProvider bool `json:"hoverProvider,omitempty"`
	// SignatureHelpProvider: Defines capabilities for signature help.
	SignatureHelpProvider *SignatureHelpOptions `json:"signatureHelpProvider,omitempty"`
	// DeclarationProvider: Defines capabilities for declaration requests.
	DeclarationProvider interface{} `json:"declarationProvider,omitempty"` // Can be boolean or DeclarationRegistrationOptions
	// DefinitionProvider: Whether the server provides definition requests.
	DefinitionProvider bool `json:"definitionProvider,omitempty"`
	// TypeDefinitionProvider: Defines capabilities for type definition requests.
	TypeDefinitionProvider interface{} `json:"typeDefinitionProvider,omitempty"` // Can be boolean or TypeDefinitionRegistrationOptions
	// ImplementationProvider: Defines capabilities for implementation requests.
	ImplementationProvider interface{} `json:"implementationProvider,omitempty"` // Can be boolean or ImplementationRegistrationOptions
	// ReferencesProvider: Whether the server provides reference requests.
	ReferencesProvider bool `json:"referencesProvider,omitempty"`
	// DocumentHighlightProvider: Whether the server provides document highlight requests.
	DocumentHighlightProvider bool `json:"documentHighlightProvider,omitempty"`
	// DocumentSymbolProvider: Defines capabilities for document symbol requests.
	DocumentSymbolProvider interface{} `json:"documentSymbolProvider,omitempty"` // Can be boolean or DocumentSymbolOptions
	// WorkspaceSymbolProvider: Whether the server provides workspace symbol requests.
	WorkspaceSymbolProvider bool `json:"workspaceSymbolProvider,omitempty"`
	// CodeActionProvider: Defines capabilities for code action requests.
	CodeActionProvider *CodeActionOptions `json:"codeActionProvider,omitempty"`
	// CodeLensProvider: Defines capabilities for code lens requests.
	CodeLensProvider *CodeLensOptions `json:"codeLensProvider,omitempty"`
	// DocumentFormattingProvider: Whether the server provides document formatting requests.
	DocumentFormattingProvider bool `json:"documentFormattingProvider,omitempty"`
	// DocumentRangeFormattingProvider: Whether the server provides document range formatting requests.
	DocumentRangeFormattingProvider bool `json:"documentRangeFormattingProvider,omitempty"`
	// RenameProvider: Defines capabilities for rename requests.
	RenameProvider interface{} `json:"renameProvider,omitempty"` // Can be boolean or RenameOptions
	// PublicationDiagnosticsProvider: Defines capabilities for publishing diagnostics.
	// Note: This is not a standard LSP capability. Usually, diagnostics are published via `textDocument/publishDiagnostics`.
	// If this is for a specific extension, it needs further definition.
	// For standard LSP, use `textDocument/publishDiagnostics`.
	// PublicationDiagnosticsProvider interface{} `json:"publicationDiagnosticsProvider,omitempty"`

	// SemanticTokensProvider: Defines capabilities for semantic token requests.
	SemanticTokensProvider interface{} `json:"semanticTokensProvider,omitempty"` // Can be SemanticTokensOptions or SemanticTokensRegistrationOptions
	// DocumentLinkProvider: Defines capabilities for document link requests.
	DocumentLinkProvider *DocumentLinkOptions `json:"documentLinkProvider,omitempty"`
	// ExecuteCommandProvider: Defines capabilities for execute command requests.
	ExecuteCommandProvider *ExecuteCommandOptions `json:"executeCommandProvider,omitempty"`
	// Workspace: Defines workspace-specific capabilities.
	Workspace interface{} `json:"workspace,omitempty"` // Can be WorkspaceOptions or WorkspaceRegistrationOptions
	// Experimental: Any experimental capabilities.
	Experimental interface{} `json:"experimental,omitempty"`
	// InlineValueProvider: Defines capabilities for inline value requests.
	InlineValueProvider interface{} `json:"inlineValueProvider,omitempty"` // Can be bool or InlineValueRegistrationOptions
	// CallHierarchyProvider: Defines capabilities for call hierarchy requests.
	CallHierarchyProvider interface{} `json:"callHierarchyProvider,omitempty"` // Can be bool or CallHierarchyRegistrationOptions
	// FoldingRangeProvider: Defines capabilities for folding range requests.
	FoldingRangeProvider interface{} `json:"foldingRangeProvider,omitempty"` // Can be bool or FoldingRangeRegistrationOptions
	// TypeHierarchyProvider: Defines capabilities for type hierarchy requests.
	TypeHierarchyProvider interface{} `json:"typeHierarchyProvider,omitempty"` // Can be bool or TypeHierarchyRegistrationOptions
	// LinkedEditingRangeProvider: Defines capabilities for linked editing range requests.
	LinkedEditingRangeProvider interface{} `json:"linkedEditingRangeProvider,omitempty"` // Can be bool or LinkedEditingRangeRegistrationOptions
}

// CompletionOptions defines options for completion requests.
type CompletionOptions struct {
	ResolveProvider bool `json:"resolveProvider,omitempty"`
	// TriggerCharacters: Characters that trigger completion.
	TriggerCharacters []string `json:"triggerCharacters,omitempty"`
	// AllCommitCharacters: All characters that commit completion.
	AllCommitCharacters []string `json:"allCommitCharacters,omitempty"`
	// CompletionItem: Capabilities related to completion items.
	CompletionItem *CompletionItemOptions `json:"completionItem,omitempty"`
}

// CompletionItemOptions represents options for completion items.
type CompletionItemOptions struct {
	// DefaultCommitChars: Default commit characters.
	DefaultCommitChars []string `json:"defaultCommitChars,omitempty"`
	// PreselectSupport: Whether to support preselection.
	PreselectSupport bool `json:"preselectSupport,omitempty"`
	// InsertTextFormat: The insert text format.
	InsertTextFormat int `json:"insertTextFormat,omitempty"`
	// InsertReplaceSupport: Whether to support insert and replace.
	InsertReplaceSupport bool `json:"insertReplaceSupport,omitempty"`
	// LabelDetailsSupport: Whether to support label details.
	LabelDetailsSupport bool `json:"labelDetailsSupport,omitempty"`
}

// SignatureHelpOptions defines options for signature help requests.
type SignatureHelpOptions struct {
	// TriggerCharacters: Characters that trigger signature help.
	TriggerCharacters []string `json:"triggerCharacters,omitempty"`
	// Re-triggerCharacters: Characters that re-trigger signature help.
	RetriggerCharacters []string `json:"retriggerCharacters,omitempty"`
}

// CodeActionOptions defines options for code action requests.
type CodeActionOptions struct {
	// CodeActionKinds: The kinds of code actions supported.
	CodeActionKinds []string `json:"codeActionKinds,omitempty"`
	// ResolveProvider: Whether to resolve code actions.
	ResolveProvider bool `json:"resolveProvider,omitempty"`
}

// CodeLensOptions defines options for code lens requests.
type CodeLensOptions struct {
	// ResolveProvider: Whether to resolve code lenses.
	ResolveProvider bool `json:"resolveProvider,omitempty"`
}

// DocumentLinkOptions defines options for document link requests.
type DocumentLinkOptions struct {
	// ResolveProvider: Whether to resolve document links.
	ResolveProvider bool `json:"resolveProvider,omitempty"`
}

// ExecuteCommandOptions defines options for execute command requests.
type ExecuteCommandOptions struct {
	// Commands: The list of commands the server supports.
	Commands []string `json:"commands,omitempty"`
}

// WorkspaceOptions defines workspace options.
type WorkspaceOptions struct {
	// WorkspaceFolders: Configuration for workspace folders.
	WorkspaceFolders *WorkspaceFoldersOptions `json:"workspaceFolders,omitempty"`
}

// WorkspaceFoldersOptions defines options for workspace folders.
type WorkspaceFoldersOptions struct {
	Supported bool `json:"supported,omitempty"`
	// Increase: If true, the server can increase the number of workspace folders.
	Increase bool `json:"increase,omitempty"`
}

// ----- LSP Text Document Structures -----

// TextDocumentItem represents a document in the client.
type TextDocumentItem struct {
	URI        string `json:"uri"`
	LanguageID string `json:"languageId"`
	Version    int    `json:"version"`
	Text       string `json:"text"`
}

// VersionedTextDocumentIdentifier represents a document with its version.
type VersionedTextDocumentIdentifier struct {
	URI     string `json:"uri"`
	Version int    `json:"version"`
}

// TextDocumentIdentifier represents a document.
type TextDocumentIdentifier struct {
	URI string `json:"uri"`
}

// TextDocumentContentChangeEvent represents a change to a document's content.
type TextDocumentContentChangeEvent struct {
	Range   *TextDocumentRange `json:"range,omitempty"`
	RangeLength *int `json:"rangeLength,omitempty"` // Deprecated in newer specs, but good to handle for compatibility
	Text    string `json:"text"`
}

// TextDocumentRange represents a range within a document.
type TextDocumentRange struct {
	Start TextDocumentPosition `json:"start"`
	End   TextDocumentPosition `json:"end"`
}

// TextDocumentPosition represents a position within a document.
type TextDocumentPosition struct {
	Line      int `json:"line"`
	Character int `json:"character"`
}

// TextDocumentPositionParams contains parameters for requests that require a position.
type TextDocumentPositionParams struct {
	TextDocument TextDocumentIdentifier `json:"textDocument"`
	Position     TextDocumentPosition `json:"position"`
}

// ----- LSP Response Structures -----

// Diagnostic represents a diagnostic, such as a compiler error or warning.
type Diagnostic struct {
	Range         TextDocumentRange `json:"range"`
	Severity      int `json:"severity,omitempty"` // 1: Error, 2: Warning, 3: Information, 4: Hint
	Code          interface{} `json:"code,omitempty"` // string or int
	Message       string `json:"message"`
	Source        string `json:"source,omitempty"`
	Tags          []int `json:"tags,omitempty"` // e.g., DiagnosticTagUnnecessary, DiagnosticTagDeprecated
	RelatedInformation []DiagnosticRelatedInformation `json:"relatedInformation,omitempty"`
	// Data is any additional data.
	Data interface{} `json:"data,omitempty"`
}

// DiagnosticRelatedInformation represents a related diagnostic information.
type DiagnosticRelatedInformation struct {
	Location TextDocumentPosition `json:"location"`
	Message  string `json:"message"`
}

// ----- Log Message Parameters -----

// LogMessageParams are parameters for the 'window/logMessage' notification.
type LogMessageParams struct {
	Type    int    `json:"type"` // 1: Log, 2: Warning, 3: Error
	Message string `json:"message"`
}

// ShowMessageParams are parameters for the 'window/showMessage' notification.
type ShowMessageParams struct {
	Type    int    `json:"type"` // 1: Error, 2: Warning, 3: Info, 4: Log
	Message string `json:"message"`
}

// ----- Main Server Logic -----

var (
	// Logger for server output.
	Logger *log.Logger
)

func init() {
	// Set up a logger that writes to stderr, so it can be seen in the editor's output.
	Logger = log.New(os.Stderr, "", log.LstdFlags)
}

// server represents the Language Server.
type server struct {
	// RPC client connection to the editor (client).
	client *rpc.Client
	// RPC server to handle incoming requests from the editor.
	rpcServer *rpc.Server

	// Stores the server's capabilities, initialized by the 'initialize' request.
	serverCapabilities *ServerCapabilities

	// Keep track of open documents.
	documents map[string]TextDocumentItem

	// Mutex to protect access to shared server state.
	mu sync.Mutex

	// Context for managing the server's lifecycle.
	ctx context.Context
	// Function to cancel the server's context.
	cancel context.CancelFunc
}

// newServer creates and initializes a new language server.
func newServer(ctx context.Context) *server {
	s := &server{
		documents: make(map[string]TextDocumentItem),
	}
	s.ctx, s.cancel = context.WithCancel(ctx)
	return s
}

// start begins the server's main loop, handling communication.
func (s *s) start() {
	Logger.Println("Starting LSP server...")

	// Use standard input/output for communication with the editor.
	// This is the most common transport for LSP.
	rpcConn := jsonrpc.NewClient(os.Stdin)
	s.client = rpcConn // Store client to send responses/notifications

	s.rpcServer = rpc.NewServer()
	// Register our server's methods. The "rpc." prefix is important for net/rpc.
	s.rpcServer.RegisterName("rpc.", s) // Register methods prefixed with "rpc."

	// Goroutine to continuously read messages from the client.
	go s.readLoop()

	// Goroutine to handle incoming requests.
	go s.handleRequests()

	// Gracefully shut down the server on interrupt signals.
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, os.Kill)
	<-sigChan // Block until a signal is received
	Logger.Println("Received shutdown signal, initiating graceful shutdown...")
	s.shutdown()
}

// readLoop continuously reads messages from the client's stdin.
func (s *s) readLoop() {
	defer s.cancel() // Signal that the server is shutting down
	decoder := json.NewDecoder(os.Stdin)
	for {
		var msg Message
		// Decode the next JSON-RPC message.
		if err := decoder.Decode(&msg); err != nil {
			if err == io.EOF {
				Logger.Println("Client closed connection.")
				return // Exit loop if client disconnects
			}
			Logger.Printf("Error decoding message: %v", err)
			// Depending on the error, you might want to send a response error
			// or simply log and continue. For critical errors, shutting down is better.
			continue
		}

		// If the message has an ID, it's a request or response.
		// If it has a method, it's a request or notification.
		// If it has result/error, it's a response.
		if msg.Method != "" {
			// This is a request or notification. Add it to the request channel.
			s.handleIncomingMessage(msg)
		} else {
			// This is a response to a request we made. (Not implemented in this basic example)
			Logger.Printf("Received unsolicited response: ID=%v, Result=%v, Error=%v", msg.ID, msg.Result, msg.Error)
		}
	}
}

// handleIncomingMessage processes a single received LSP message.
func (s *s) handleIncomingMessage(msg Message) {
	// We can use a separate goroutine for each message to avoid blocking the read loop.
	go func() {
		select {
		case <-s.ctx.Done():
			// If the server is shutting down, ignore new messages.
			return
		default:
			// Log received messages for debugging.
			log.Printf("Received Message: Method=%s, ID=%v", msg.Method, msg.ID)

			// Route the message to the appropriate handler.
			// We prepend "rpc." because that's how we registered the methods.
			methodFullName := "rpc." + msg.Method
			if s.rpcServer.HasMethod(methodFullName) {
				// Use the net/rpc framework to dispatch the call.
				// This is a bit of a workaround because net/rpc is synchronous,
				// but we're passing it a channel to simulate async handling.
				// In a real-world, more robust server, you might use a custom JSON-RPC multiplexer.
				s.rpcServer.ServeCodec(jsonrpc.NewServerCodec(s.readerForMethod(msg)))
			} else {
				// If the method is not registered, send an unknown method error.
				s.sendErrorResponse(msg.ID, -32601, fmt.Sprintf("Method not found: %s", msg.Method))
			}
		}
	}()
}

// readerForMethod creates a mock io.Reader for a specific message to be consumed by ServeCodec.
// This is a hacky way to make net/rpc work with our JSON-RPC parsing.
// A cleaner approach would be a dedicated JSON-RPC server implementation.
func (s *s) readerForMethod(msg Message) io.Reader {
	// Marshal the single message back into JSON.
	payload, err := json.Marshal(msg)
	if err != nil {
		Logger.Printf("Error marshalling message for ServeCodec: %v", err)
		return strings.NewReader("") // Return empty reader on error
	}

	// Construct the content-length header.
	header := fmt.Sprintf("Content-Length: %d\r\n\r\n", len(payload))
	fullMessage := header + string(payload)

	return strings.NewReader(fullMessage)
}

// handleRequests is now implicitly handled by the rpcServer and readLoop.
// The core logic of dispatching is within handleIncomingMessage.

// shutdown performs graceful shutdown of the server.
func (s *s) shutdown() {
	s.cancel() // Cancel the context to signal shutdown to goroutines.
	// In a real server, you'd send a `exit` notification to the client if applicable,
	// perform cleanup (e.g., closing files, saving state), and then exit.
	Logger.Println("Server shutdown complete.")
	os.Exit(0) // Exit the process.
}

// sendMessage sends an LSP message to the client.
func (s *s) sendMessage(msg Message) {
	payload, err := json.Marshal(msg)
	if err != nil {
		Logger.Printf("Error marshalling message: %v", err)
		return
	}

	// LSP messages are preceded by Content-Length header.
	contentLength := fmt.Sprintf("Content-Length: %d\r\n\r\n", len(payload))
	// Write header and payload to stdout.
	if _, err := io.WriteString(os.Stdout, contentLength); err != nil {
		Logger.Printf("Error writing Content-Length header: %v", err)
		return
	}
	if _, err := os.Stdout.Write(payload); err != nil {
		Logger.Printf("Error writing message payload: %v", err)
		return
	}
	// Ensure the output is flushed immediately.
	if flusher, ok := os.Stdout.(interface{ Flush() error }); ok {
		if err := flusher.Flush(); err != nil {
			Logger.Printf("Error flushing stdout: %v", err)
		}
	}
	log.Printf("Sent Message: Method=%s, ID=%v", msg.Method, msg.ID)
}

// sendErrorResponse sends an error response for a given request ID.
func (s *s) sendErrorResponse(id interface{}, code int, message string) {
	errResp := ResponseError{
		Code:    code,
		Message: message,
	}
	response := Message{
		Version: "2.0",
		ID:      id,
		Error:   &errResp,
	}
	s.sendMessage(response)
}

// sendNotification sends a notification to the client.
func (s *s) sendNotification(method string, params interface{}) {
	notification := Message{
		Version: "2.0",
		Method:  method,
		Params:  nil, // Params will be marshaled below
	}
	if params != nil {
		// Marshal params into a RawMessage for the Message struct.
		paramsBytes, err := json.Marshal(params)
		if err != nil {
			Logger.Printf("Error marshalling notification params for %s: %v", method, err)
			return
		}
		rawParams := json.RawMessage(paramsBytes)
		notification.Params = &rawParams
	}
	s.sendMessage(notification)
}

// ----- RPC Methods for LSP Handler -----
// These methods are exposed via net/rpc, hence the "rpc." prefix in registration.
// The LSP method names (e.g., "initialize") are used within the Message.Method field.

// RPCHandleInitialize handles the 'initialize' request from the client.
// This is the first request sent by a client.
func (s *s) RPCHandleInitialize(paramsJSON *json.RawMessage, result *interface{}) error {
	var params InitializeParams
	if err := json.Unmarshal(*paramsJSON, &params); err != nil {
		Logger.Printf("Error unmarshalling initialize params: %v", err)
		return fmt.Errorf("invalid params for initialize request: %w", err)
	}

	Logger.Printf("Received initialize request from client: %s %s", params.ClientInfo.Name, params.ClientInfo.Version)
	Logger.Printf("Client capabilities: %+v", params.Capabilities)

	// Configure server capabilities here based on what your language server will support.
	s.serverCapabilities = &ServerCapabilities{
		// TextDocumentSync: 1, // 1: Full document sync. Use 2 for incremental.
		TextDocumentSync: 1, // Start with Full sync.
		HoverProvider:    true, // Example: Enable hover provider.
		DefinitionProvider: true, // Example: Enable definition provider.
		DocumentSymbolProvider: true, // Example: Enable document symbol provider.
		// Add more capabilities as you implement them.
		// For example, completion provider:
		CompletionProvider: &CompletionOptions{
			ResolveProvider: false, // Set to true if you want to support completion item resolution.
			TriggerCharacters: []string{".", "("}, // Characters that trigger completion.
		},
		// SemanticTokensProvider: SomeSemanticTokenProviderOption, // Placeholder
	}

	// Log the capabilities we are offering.
	Logger.Printf("Server capabilities: %+v", s.serverCapabilities)

	// Prepare the InitializeResult.
	initializeResult := InitializeResult{
		Capabilities: *s.serverCapabilities,
		ServerInfo: &ServerInfo{
			Name:    "MyGoLangServer",
			Version: "1.0.0",
		},
	}

	// Assign the result to the output parameter.
	*result = initializeResult
	return nil
}

// RPCHandleInitialized handles the 'initialized' notification.
// This notification is sent by the client after the 'initialize' handshake.
func (s *s) RPCHandleInitialized(paramsJSON *json.RawMessage) error {
	Logger.Println("Received 'initialized' notification from client.")
	// At this point, the client is ready to receive notifications.
	// You can send dynamic registration requests or initial configuration here if needed.
	// Example: Send a notification to the client
	s.sendNotification("window/logMessage", LogMessageParams{
		Type:    3, // Info
		Message: "Go LSP Server initialized successfully!",
	})
	return nil
}

// RPCHandleShutdown handles the 'shutdown' request.
// This request asks the server to shut down, but to be still able to restart.
func (s *s) RPCHandleShutdown(paramsJSON *json.RawMessage, result *interface{}) error {
	Logger.Println("Received 'shutdown' request from client.")
	// In a real server, you would perform cleanup here.
	// For now, we just acknowledge it and prepare to exit.
	*result = nil // The result for shutdown is typically null.
	// The client will then send an 'exit' notification to actually terminate the process.
	return nil
}

// RPCHandleExit handles the 'exit' notification.
// This notification signals the server to terminate.
func (s *s) RPCHandleExit(paramsJSON *json.RawMessage) error {
	Logger.Println("Received 'exit' notification from client. Shutting down.")
	// The server should exit after receiving this notification.
	go func() {
		// Give the last message a moment to be sent before exiting.
		time.Sleep(100 * time.Millisecond)
		s.shutdown()
	}()
	return nil
}

// RPCHandleDidChangeConfiguration handles 'workspace/didChangeConfiguration' notification.
func (s *s) RPCHandleDidChangeConfiguration(paramsJSON *json.RawMessage) error {
	var params struct {
		Settings interface{} `json:"settings"`
	}
	if err := json.Unmarshal(*paramsJSON, &params); err != nil {
		Logger.Printf("Error unmarshalling didChangeConfiguration params: %v", err)
		return fmt.Errorf("invalid params for workspace/didChangeConfiguration: %w", err)
	}
	Logger.Printf("Received configuration update: %v", params.Settings)
	// Process the new settings here.
	return nil
}

// RPCHandleDidOpenTextDocument handles 'textDocument/didOpen' notification.
func (s *s) RPCHandleDidOpenTextDocument(paramsJSON *json.RawMessage) error {
	var params DidOpenTextDocumentParams
	if err := json.Unmarshal(*paramsJSON, &params); err != nil {
		Logger.Printf("Error unmarshalling didOpenTextDocument params: %v", err)
		return fmt.Errorf("invalid params for textDocument/didOpen: %w", err)
	}

	s.mu.Lock()
	s.documents[params.TextDocument.URI] = params.TextDocument
	s.mu.Unlock()

	Logger.Printf("Opened document: URI=%s, LanguageID=%s, Version=%d",
		params.TextDocument.URI, params.TextDocument.LanguageID, params.TextDocument.Version)

	// Perform initial analysis and potentially send diagnostics.
	// For now, we'll just log.
	s.publishDiagnostics(params.TextDocument.URI, params.TextDocument.Version, []Diagnostic{
		{
			Range: TextDocumentRange{
				Start: TextDocumentPosition{Line: 0, Character: 0},
				End:   TextDocumentPosition{Line: 0, Character: 1},
			},
			Severity: 3, // Information
			Message:  fmt.Sprintf("Document %s opened successfully. Language: %s", params.TextDocument.URI, params.TextDocument.LanguageID),
		},
	})

	return nil
}

// RPCHandleDidChangeTextDocument handles 'textDocument/didChange' notification.
func (s *s) RPCHandleDidChangeTextDocument(paramsJSON *json.RawMessage) error {
	var params DidChangeTextDocumentParams
	if err := json.Unmarshal(*paramsJSON, &params); err != nil {
		Logger.Printf("Error unmarshalling didChangeTextDocument params: %v", err)
		return fmt.Errorf("invalid params for textDocument/didChange: %w", err)
	}

	s.mu.Lock()
	doc, ok := s.documents[params.TextDocument.URI]
	if !ok {
		Logger.Printf("Document %s not found for didChange. It might have been closed.", params.TextDocument.URI)
		s.mu.Unlock()
		return nil // Document not open, nothing to do.
	}

	// Apply changes. For simplicity, we're only handling full document updates here.
	// Incremental updates are more complex and require tracking textDocumentContentChanges.
	// In a real server, you'd apply the changes to the existing document.
	// Here, we assume the first contentChange contains the full text or a diff.
	if len(params.ContentChanges) > 0 {
		// For simplicity, we assume incremental changes or a full text update.
		// A robust server would handle 'range' and 'rangeLength' correctly for incremental updates.
		// If the change is a full document update, the `range` field is omitted.
		if params.ContentChanges[0].Range == nil {
			doc.Text = params.ContentChanges[0].Text
		} else {
			// This is an incremental change. Applying it correctly is complex.
			// For this example, we'll just log it.
			Logger.Printf("Received incremental change for %s: Text=%s, Range=%+v",
				params.TextDocument.URI, params.ContentChanges[0].Text, params.ContentChanges[0].Range)
			// A real implementation would carefully apply the text change.
			// For now, we'll just update the document text based on the first change.
			// This is INCORRECT for true incremental changes if there are multiple changes or ranges.
			// A correct implementation would reconstruct the text.
			doc.Text = applyIncrementalChange(doc.Text, params.ContentChanges[0])
		}
	}
	doc.Version = params.TextDocument.Version // Update version
	s.documents[params.TextDocument.URI] = doc
	s.mu.Unlock()

	Logger.Printf("Changed document: URI=%s, Version=%d", params.TextDocument.URI, params.TextDocument.Version)

	// Perform analysis on the changed document and send diagnostics.
	// Replace this with your actual language analysis.
	s.publishDiagnostics(doc.URI, doc.Version, []Diagnostic{
		{
			Range: TextDocumentRange{
				Start: TextDocumentPosition{Line: 1, Character: 0},
				End:   TextDocumentPosition{Line: 1, Character: 5},
			},
			Severity: 2, // Warning
			Message:  fmt.Sprintf("Document %s changed. Version: %d. (Placeholder warning)", doc.URI, doc.Version),
		},
	})

	return nil
}

// RPCHandleDidCloseTextDocument handles 'textDocument/didClose' notification.
func (s *s) RPCHandleDidCloseTextDocument(paramsJSON *json.RawMessage) error {
	var params TextDocumentIdentifier
	if err := json.Unmarshal(*paramsJSON, &params); err != nil {
		Logger.Printf("Error unmarshalling didCloseTextDocument params: %v", err)
		return fmt.Errorf("invalid params for textDocument/didClose: %w", err)
	}

	s.mu.Lock()
	delete(s.documents, params.URI)
	s.mu.Unlock()

	Logger.Printf("Closed document: URI=%s", params.URI)

	// Clear diagnostics for the closed document.
	s.publishDiagnostics(params.URI, 0, nil) // Version 0 indicates no document associated.

	return nil
}

// RPCHandleDidSaveTextDocument handles 'textDocument/didSave' notification.
func (s *s) RPCHandleDidSaveTextDocument(paramsJSON *json.RawMessage) error {
	var params DidSaveTextDocumentParams
	if err := json.Unmarshal(*paramsJSON, &params); err != nil {
		Logger.Printf("Error unmarshalling didSaveTextDocument params: %v", err)
		return fmt.Errorf("invalid params for textDocument/didSave: %w", err)
	}

	Logger.Printf("Saved document: URI=%s", params.TextDocument.URI)
	// Perform actions on save, e.g., formatting, running linters, etc.
	return nil
}

// RPCHandleCompletion handles 'textDocument/completion' request.
func (s *s) RPCHandleCompletion(paramsJSON *json.RawMessage, result *interface{}) error {
	var params TextDocumentPositionParams
	if err := json.Unmarshal(*paramsJSON, &params); err != nil {
		Logger.Printf("Error unmarshalling completion params: %v", err)
		return fmt.Errorf("invalid params for textDocument/completion: %w", err)
	}

	Logger.Printf("Received completion request for %s at position %d:%d",
		params.TextDocument.URI, params.Position.Line, params.Position.Character)

	// Placeholder: Return some dummy completion items.
	// You'll need to implement actual logic based on your language.
	completionItems := []CompletionItem{
		{
			Label:         "exampleCompletionItem",
			Kind:          1, // CompletionItemKindText
			Detail:        "A sample completion item.",
			Documentation: "This is a placeholder completion item.",
		},
		{
			Label: "anotherItem",
			Kind:  3, // CompletionItemKindMethod
			Detail: "Another example method",
			InsertText: "anotherItem();",
		},
	}

	*result = completionItems
	return nil
}

// RPCHandleDefinition handles 'textDocument/definition' request.
func (s *s) RPCHandleDefinition(paramsJSON *json.RawMessage, result *interface{}) error {
	var params TextDocumentPositionParams
	if err := json.Unmarshal(*paramsJSON, &params); err != nil {
		Logger.Printf("Error unmarshalling definition params: %v", err)
		return fmt.Errorf("invalid params for textDocument/definition: %w", err)
	}

	Logger.Printf("Received definition request for %s at position %d:%d",
		params.TextDocument.URI, params.Position.Line, params.Position.Character)

	// Placeholder: Return a dummy definition location.
	// Implement actual logic to find definitions in your language.
	definitionLocation := Location{
		URI: params.TextDocument.URI,
		Range: TextDocumentRange{
			Start: TextDocumentPosition{Line: 5, Character: 0},
			End:   TextDocumentPosition{Line: 5, Character: 10},
		},
	}

	*result = definitionLocation
	return nil
}

// RPCHandleDocumentSymbol handles 'textDocument/symbol' request.
func (s *s) RPCHandleDocumentSymbol(paramsJSON *json.RawMessage, result *interface{}) error {
	var params DocumentSymbolParams
	if err := json.Unmarshal(*paramsJSON, &params); err != nil {
		Logger.Printf("Error unmarshalling documentSymbol params: %v", err)
		return fmt.Errorf("invalid params for textDocument/symbol: %w", err)
	}

	Logger.Printf("Received document symbol request for %s", params.TextDocument.URI)

	// Placeholder: Return some dummy document symbols.
	symbols := []interface{}{ // Use interface{} because it can be SymbolInformation or DocumentSymbol
		SymbolInformation{ // Older format, might be supported by some clients
			Name:          "sampleFunction",
			Kind:          12, // SymbolKindFunction
			Location:      Location{URI: params.TextDocument.URI, Range: TextDocumentRange{Start: TextDocumentPosition{Line: 10, Character: 0}, End: TextDocumentPosition{Line: 10, Character: 10}}},
			ContainerName: "myFile",
		},
		DocumentSymbol{ // Newer format
			Name: "SampleClass",
			Kind: 10, // SymbolKindClass
			Range: TextDocumentRange{Start: TextDocumentPosition{Line: 20, Character: 0}, End: TextDocumentPosition{Line: 30, Character: 0}},
			SelectionRange: TextDocumentRange{Start: TextDocumentPosition{Line: 20, Character: 0}, End: TextDocumentPosition{Line: 20, Character: 5}},
			Children: []DocumentSymbol{ // Example of nested symbols
				{
					Name: "sampleMethod",
					Kind: 12, // SymbolKindMethod
					Range: TextDocumentRange{Start: TextDocumentPosition{Line: 22, Character: 4}, End: TextDocumentPosition{Line: 22, Character: 10}},
					SelectionRange: TextDocumentRange{Start: TextDocumentPosition{Line: 22, Character: 4}, End: TextDocumentPosition{Line: 22, Character: 14}},
				},
			},
		},
	}

	*result = symbols
	return nil
}

// RPCHandleHover handles 'textDocument/hover' request.
func (s *s) RPCHandleHover(paramsJSON *json.RawMessage, result *interface{}) error {
	var params TextDocumentPositionParams
	if err := json.Unmarshal(*paramsJSON, &params); err != nil {
		Logger.Printf("Error unmarshalling hover params: %v", err)
		return fmt.Errorf("invalid params for textDocument/hover: %w", err)
	}

	Logger.Printf("Received hover request for %s at position %d:%d",
		params.TextDocument.URI, params.Position.Line, params.Position.Character)

	// Placeholder: Return dummy hover content.
	hoverContent := Hover{
		Contents: MarkedString{Language: "plaintext", Value: fmt.Sprintf("Hover info for %s at %d:%d\n(This is a placeholder)", params.TextDocument.URI, params.Position.Line, params.Position.Character)},
		Range: &TextDocumentRange{ // Optional range
			Start: TextDocumentPosition{Line: params.Position.Line, Character: params.Position.Character},
			End:   TextDocumentPosition{Line: params.Position.Line, Character: params.Position.Character + 1},
		},
	}

	*result = hoverContent
	return nil
}

// RPCHandleCodeAction handles 'textDocument/codeAction' request.
func (s *s) RPCHandleCodeAction(paramsJSON *json.RawMessage, result *interface{}) error {
	var params CodeActionParams
	if err := json.Unmarshal(*paramsJSON, &params); err != nil {
		Logger.Printf("Error unmarshalling codeAction params: %v", err)
		return fmt.Errorf("invalid params for textDocument/codeAction: %w", err)
	}

	Logger.Printf("Received codeAction request for %s, context: %+v", params.TextDocument.URI, params.Context)

	// Placeholder: Return some dummy code actions.
	codeActions := []interface{}{ // Can be CodeAction or Command
		CodeAction{
			Title: "Fix placeholder warning",
			Kind:  "quickfix",
			Edit: &WorkspaceEdit{
				Changes: map[string][]TextEdit{
					params.TextDocument.URI: {
						{
							Range: TextDocumentRange{
								Start: TextDocumentPosition{Line: 1, Character: 0},
								End:   TextDocumentPosition{Line: 1, Character: 5},
							},
							NewText: "fixed",
						},
					},
				},
			},
			IsPreferred: true,
		},
		// Example of a command without edit
		Command{
			Command:   "myExtension.runCustomAction",
			Title:     "Run custom action",
			Arguments: []interface{}{params.TextDocument.URI},
		},
	}

	*result = codeActions
	return nil
}

// RPCHandleExecuteCommand handles 'workspace/executeCommand' request.
func (s *s) RPCHandleExecuteCommand(paramsJSON *json.RawMessage, result *interface{}) error {
	var params ExecuteCommandParams
	if err := json.Unmarshal(*paramsJSON, &params); err != nil {
		Logger.Printf("Error unmarshalling executeCommand params: %v", err)
		return fmt.Errorf("invalid params for workspace/executeCommand: %w", err)
	}

	Logger.Printf("Received executeCommand request: Command=%s, Arguments=%v", params.Command, params.Arguments)

	// Handle commands here.
	switch params.Command {
	case "myExtension.runCustomAction":
		if len(params.Arguments) > 0 {
			uri, ok := params.Arguments[0].(string)
			if ok {
				Logger.Printf("Executing custom action for URI: %s", uri)
				// Perform action...
				*result = "Custom action executed successfully"
			} else {
				return fmt.Errorf("invalid argument for myExtension.runCustomAction: expected string URI")
			}
		} else {
			return fmt.Errorf("missing argument for myExtension.runCustomAction")
		}
	default:
		return fmt.Errorf("unknown command: %s", params.Command)
	}

	return nil
}

// RPCHandleOther RPC handlers for methods not explicitly listed above.
// This is a catch-all for any other LSP requests the server might receive.
// You will need to implement specific handlers for methods your server supports.
func (s *s) RPCHandleOther(method string, paramsJSON *json.RawMessage, result *interface{}) error {
	Logger.Printf("Received unhandled RPC: Method=%s, Params=%s", method, string(*paramsJSON))

	// If your server supports a method but it's not explicitly handled above,
	// you would add it to the switch in `handleIncomingMessage` and define
	// its handler here or as a separate `RPCHandle<MethodName>` function.
	// For now, we'll return a "method not implemented" error.
	return fmt.Errorf("unimplemented RPC method: %s", method)
}

// ----- Helper Methods for LSP Features -----

// publishDiagnostics sends diagnostic information to the client for a specific document.
func (s *s) publishDiagnostics(uri string, version int, diagnostics []Diagnostic) {
	params := PublishDiagnosticsParams{
		URI:         uri,
		Version:     version,
		Diagnostics: diagnostics,
	}
	s.sendNotification("textDocument/publishDiagnostics", params)
}

// ----- LSP Specific Data Structures -----

// DidOpenTextDocumentParams for textDocument/didOpen.
type DidOpenTextDocumentParams struct {
	TextDocument TextDocumentItem `json:"textDocument"`
}

// DidChangeTextDocumentParams for textDocument/didChange.
type DidChangeTextDocumentParams struct {
	TextDocument TextDocumentIdentifier `json:"textDocument"`
	ContentChanges []TextDocumentContentChangeEvent `json:"contentChanges"`
}

// DidSaveTextDocumentParams for textDocument/didSave.
type DidSaveTextDocumentParams struct {
	TextDocument TextDocumentIdentifier `json:"textDocument"`
	Text         *string `json:"text,omitempty"` // Optional: if the client is configured to send the content on save.
}

// Location represents a location in a resource.
type Location struct {
	URI   string `json:"uri"`
	Range Range  `json:"range"`
}

// Range represents a range in a text document.
type Range struct {
	Start Position `json:"start"`
	End   Position `json:"end"`
}

// Position represents a position in a text document.
type Position struct {
	Line      int `json:"line"`
	Character int `json:"character"`
}

// Hover represents a hover response.
type Hover struct {
	Contents interface{} `json:"contents"` // Can be MarkedString, MarkedString array, or MarkupContent
	Range    *Range      `json:"range,omitempty"`
}

// MarkedString can be a markdown string or a object with language and value.
type MarkedString struct {
	Language string `json:"language,omitempty"`
	Value    string `json:"value"`
}

// MarkupContent represents a string with a specific markup language.
type MarkupContent struct {
	Kind  string `json:"kind"` // "plaintext" or "markdown"
	Value string `json:"value"`
}

// CompletionItem represents a completion item.
type CompletionItem struct {
	Label         string `json:"label"`
	Kind          int `json:"kind,omitempty"` // 1: Text, 2: Method, 3: Function, 4: Constructor, 5: Field, 6: Variable, 7: Class, 8: Interface, 9: Module, 10: Property, 11: Unit, 12: Value, 13: Enum, 14: Keyword, 15: Snippet, 16: Color, 17: File, 18: Reference, 19: Folder, 20: Snippet, 21: Text (deprecated)
	Tags          []int `json:"tags,omitempty"` // e.g., CompletionItemTagDeprecated
	Detail        string `json:"detail,omitempty"`
	Documentation interface{} `json:"documentation,omitempty"` // string, MarkupContent, or null
	Deprecated    bool `json:"deprecated,omitempty"`
	Preselect     bool `json:"preselect,omitempty"`
	SortText      string `json:"sortText,omitempty"`
	FilterText    string `json:"filterText,omitempty"`
	InsertText    string `json:"insertText,omitempty"`
	InsertTextFormat int `json:"insertTextFormat,omitempty"` // 1: PlainText, 2: Snippet
	InsertMode    int `json:"insertMode,omitempty"` // 1: AsIs, 2: AdjustIndentation
	TextEdit      *TextEdit `json:"textEdit,omitempty"`
	// AdditionalTextEdits is a list of TextEdits to perform.
	AdditionalTextEdits []TextEdit `json:"additionalTextEdits,omitempty"`
	CommitCharacters    []string `json:"commitCharacters,omitempty"`
	// Data is for the server to send to the client.
	Data interface{} `json:"data,omitempty"`
	// Range is for completion items that replace a range of text.
	Range *Range `json:"range,omitempty"`
}

// SymbolInformation represents a symbol that describes a resource.
type SymbolInformation struct {
	Name          string   `json:"name"`
	Kind          int      `json:"kind"` // SymbolKind
	Location      Location `json:"location"`
	ContainerName string   `json:"containerName,omitempty"`
}

// DocumentSymbol represents a symbol in a document.
type DocumentSymbol struct {
	Name           string `json:"name"`
	Kind           int `json:"kind"` // SymbolKind
	Deprecated     bool `json:"deprecated,omitempty"`
	Range          Range `json:"range"`
	SelectionRange Range `json:"selectionRange"`
	Children       []DocumentSymbol `json:"children,omitempty"`
}

// CodeAction represents a code action that can be offered to a user.
type CodeAction struct {
	Title              string `json:"title"`
	Kind               string `json:"kind,omitempty"` // e.g., "quickfix", "refactor", "source"
	Diagnose           *Diagnostic `json:"diagnose,omitempty"`
	Edit               *WorkspaceEdit `json:"edit,omitempty"`
	Command            *Command `json:"command,omitempty"`
	IsPreferred        bool `json:"isPreferred,omitempty"`
	DisabledSupport    bool `json:"disabledSupport,omitempty"`
	Data               interface{} `json:"data,omitempty"`
	// Arguments for the command.
	Arguments []interface{} `json:"arguments,omitempty"`
}

// Command represents a command.
type Command struct {
	Title     string        `json:"title"`
	Command   string        `json:"command"`
	Arguments []interface{} `json:"arguments,omitempty"`
}

// WorkspaceEdit represents a edit to a workspace.
type WorkspaceEdit struct {
	Changes           map[string][]TextEdit `json:"changes,omitempty"`
	DocumentChanges   []interface{} `json:"documentChanges,omitempty"` // Can be TextDocumentEdit, CreateFile, DeleteFile, RenameFile
	Message           string `json:"message,omitempty"`
	Transactional     bool `json:"transactional,omitempty"`
}

// TextEdit represents a text edit.
type TextEdit struct {
	Range   Range `json:"range"`
	NewText string `json:"newText"`
}

// PublishDiagnosticsParams for textDocument/publishDiagnostics notification.
type PublishDiagnosticsParams struct {
	URI         string `json:"uri"`
	Version     int `json:"version,omitempty"` // The version of the document the diagnostics are for.
	Diagnostics []Diagnostic `json:"diagnostics"`
}

// CodeActionParams for textDocument/codeAction request.
type CodeActionParams struct {
	TextDocument TextDocumentIdentifier `json:"textDocument"`
	Range        Range `json:"range"`
	Context      CodeActionContext `json:"context"`
}

// CodeActionContext is the context of a code action request.
type CodeActionContext struct {
	// Diagnostics: An array of diagnostics this code action is associated with.
	Diagnostics []Diagnostic `json:"diagnostics"`
	// Only: Filter the kinds of code actions to be returned.
	Only []string `json:"only,omitempty"`
	// TriggerKind: Indicates the reason the code action was requested.
	TriggerKind int `json:"triggerKind,omitempty"` // 1: Invoked, 2: Automatic
}

// ExecuteCommandParams for workspace/executeCommand request.
type ExecuteCommandParams struct {
	Command string        `json:"command"`
	Arguments []interface{} `json:"arguments,omitempty"`
}

// ----- Utility Functions -----

// applyIncrementalChange is a helper to apply text changes.
// This is a simplified implementation and may not handle all edge cases.
func applyIncrementalChange(originalText string, change TextDocumentContentChangeEvent) string {
	if change.Range == nil { // Full document update
		return change.Text
	}

	// Convert original text to lines for easier manipulation.
	originalLines := strings.Split(originalText, "\n")

	// Calculate start and end indices of the change in the original text.
	startLine := change.Range.Start.Line
	startChar := change.Range.Start.Character
	endLine := change.Range.End.Line
	endChar := change.Range.End.Character

	// Get the lines that are affected by the change.
	var affectedLines []string
	if startLine == endLine {
		// Change is within a single line.
		line := originalLines[startLine]
		affectedLines = append(affectedLines, line[:startChar]+change.Text+line[endChar:])
	} else {
		// Change spans multiple lines.
		// Part of the start line.
		lineStart := originalLines[startLine]
		affectedLines = append(affectedLines, lineStart[:startChar]+change.Text)

		// Intermediate lines (if any). These are completely replaced.
		// The new text might contain newlines, so we need to split it.
		// However, if `change.Text` contains newlines, it's a multi-line insert.
		// The `change.Text` should replace the content from start to end.

		// A more robust way is to construct the new text piece by piece:
		var newLines []string
		// Add lines before the start line
		newLines = append(newLines, originalLines[:startLine]...)
		// Add the modified start line
		newLines = append(newLines, lineStart[:startChar] + change.Text + originalLines[endLine][endChar:])
		// Add lines after the end line
		newLines = append(newLines, originalLines[endLine+1:]...)

		return strings.Join(newLines, "\n")
	}

	// Reconstruct the text.
	var newLines []string
	newLines = append(newLines, originalLines[:startLine]...)
	newLines = append(newLines, affectedLines...)
	newLines = append(newLines, originalLines[endLine+1:]...)

	return strings.Join(newLines, "\n")
}

func main() {
	// Create a context that can be cancelled.
	ctx := context.Background()
	server := newServer(ctx)

	// Start the server's communication loop.
	server.start()
	}*/
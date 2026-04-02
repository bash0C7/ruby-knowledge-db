require 'mcp'
require 'mcp/server/transports/stdio_transport'
require_relative 'query_tool'
require_relative 'schema_resource'
require_relative 'semantic_search_tool'

module ChiebukuroMcp
  class Server
    def initialize(db_path:, embedder:)
      @db_path = db_path
      @query_tool           = QueryTool.new(db_path)
      @schema_resource      = SchemaResource.new(db_path)
      @semantic_search_tool = SemanticSearchTool.new(db_path, embedder: embedder)
    end

    def build_mcp_server
      query_tool            = @query_tool
      schema_resource       = @schema_resource
      semantic_search_tool  = @semantic_search_tool

      # Tool: query — SELECT のみ許可
      query_tool_class = MCP::Tool.define(
        name: 'query',
        description: 'Execute a read-only SELECT query against the Ruby knowledge SQLite database',
        input_schema: {
          type: 'object',
          properties: {
            sql: {
              type: 'string',
              description: 'SQL SELECT statement to execute'
            }
          },
          required: ['sql']
        }
      ) do |sql:|
        result = query_tool.call(sql: sql)
        MCP::Tool::Response.new([{ type: 'text', text: result }])
      rescue ArgumentError => e
        MCP::Tool::Response.new([{ type: 'text', text: e.message }], error: true)
      rescue => e
        MCP::Tool::Response.new([{ type: 'text', text: e.message }], error: true)
      end

      # Resource: schema://database — スキーマ説明
      schema_res = MCP::Resource.new(
        uri: 'schema://database',
        name: 'database_schema',
        description: 'SQLite database schema with table and column descriptions',
        mime_type: 'text/markdown'
      )

      # Tool: semantic_search — 自然言語クエリ → vec0 KNN 検索
      semantic_search_tool_class = MCP::Tool.define(
        name: 'semantic_search',
        description: 'Semantic similarity search using vector embeddings (768-dim ruri-v3). Returns top-N most relevant Ruby knowledge entries.',
        input_schema: {
          type: 'object',
          properties: {
            query: { type: 'string',  description: 'Natural language search query' },
            limit: { type: 'integer', description: 'Number of results to return (default: 5)' }
          },
          required: ['query']
        }
      ) do |query:, limit: 5|
        result = semantic_search_tool.call(query: query, limit: limit)
        MCP::Tool::Response.new([{ type: 'text', text: result }])
      rescue => e
        MCP::Tool::Response.new([{ type: 'text', text: e.message }], error: true)
      end

      server = MCP::Server.new(
        name: 'chiebukuro-mcp',
        version: '0.1.0',
        tools: [query_tool_class, semantic_search_tool_class],
        resources: [schema_res]
      )

      server.resources_read_handler do |params|
        uri = params[:uri]
        if uri == 'schema://database'
          content = schema_resource.call
          [{ uri: uri, mimeType: 'text/markdown', text: content }]
        else
          []
        end
      end

      server
    end

    def run
      server = build_mcp_server
      transport = MCP::Server::Transports::StdioTransport.new(server)
      transport.open
    end
  end
end

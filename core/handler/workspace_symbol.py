from core.handler import Handler
from core.utils import eval_in_emacs


class WorkspaceSymbol(Handler):
    name = "workspace_symbol"
    method = "workspace/symbol"
    provider = "workspace_symbol_provider"

    def process_request(self, query) -> dict:
        return dict(query=query)

    def process_response(self, response: dict) -> None:
        print('workspace_symbol:', response)
        if response is not None:
            eval_in_emacs("lsp-bridge-show-workspace-symbols", response)

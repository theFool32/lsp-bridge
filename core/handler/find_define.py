from core.handler import Handler
from core.utils import *
from typing import Union


class FindDefine(Handler):
    name = "find_define"
    method = "textDocument/definition"
    cancel_on_change = True

    def process_request(self, position) -> dict:
        return dict(position=position)

    def process_response(self, response: Union[dict, list]) -> None:
        if not response:
            message_emacs("No definition found.")
            eval_in_emacs("lsp-bridge--jump-to-def", None, None)
            return

        file_info = response[0] if isinstance(response, list) else response
        # volar return only LocationLink (using targetUri)
        file_uri = file_info["uri"] if "uri" in file_info else file_info["targetUri"]
        range1 = file_info["range"] if "range" in file_info else file_info["targetRange"]
        start_pos = range1["start"]

        if file_uri.startswith("jdt://"):
            # for java
            self.file_action.handlers["jdt_uri_resolver"].send_request(file_uri, start_pos)
        elif file_uri.startswith("csharp://"):
            # for csharp
            eval_in_emacs("lsp-bridge--jump-to-def", None, None)
            raise NotImplementedError()
        elif file_uri.startswith("jar://"):
            # for clojure
            eval_in_emacs("lsp-bridge--jump-to-def", None, None)
            raise NotImplementedError()
        else:
            # for normal file uri
            filepath = uri_to_path(file_uri)
            self.file_action.lsp_bridge.create_file_action(
                filepath=filepath,
                lang_server_info=self.file_action.lang_server_info,
                lsp_server=self.file_action.lsp_server,
            )
            eval_in_emacs("lsp-bridge--jump-to-def", filepath, start_pos)

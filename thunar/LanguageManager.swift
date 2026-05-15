//
//  LanguageManager.swift
//  thunder
//
//  Created by Carlos Felipe Araújo on 14/05/26.
//

import Combine
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case ptBR = "pt-BR"
    case en

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ptBR: return "Português (Brasil)"
        case .en: return "English"
        }
    }
}

class LanguageManager: ObservableObject {
    @Published var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: "appLanguage")
            // Atualiza a preferência global do sistema para este app
            UserDefaults.standard.set([currentLanguage.rawValue], forKey: "AppleLanguages")
        }
    }

    static let shared = LanguageManager()

    private init() {
        let saved = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.ptBR.rawValue
        currentLanguage = AppLanguage(rawValue: saved) ?? .ptBR
    }

    func local(_ key: String) -> String {
        return Translations.getText(key, for: currentLanguage)
    }
}

enum Translations {
    static func getText(_ key: String, for lang: AppLanguage) -> String {
        let dict: [String: [AppLanguage: String]] = [
            "settings": [.ptBR: "Configurações", .en: "Settings"],
            "sidebar": [.ptBR: "Barra Lateral", .en: "Sidebar"],
            "general": [.ptBR: "Geral", .en: "General"],
            "language": [.ptBR: "Idioma", .en: "Language"],
            "about_thunder": [.ptBR: "Sobre o Thunder", .en: "About Thunder"],
            "favorites": [.ptBR: "Favoritos", .en: "Favorites"],
            "devices": [.ptBR: "Dispositivos", .en: "Devices"],
            "tags": [.ptBR: "Etiquetas", .en: "Tags"],
            "show_items_sidebar": [.ptBR: "Mostrar estes itens na barra lateral:", .en: "Show these items in the sidebar:"],
            "sections": [.ptBR: "Seções:", .en: "Sections:"],
            "by": [.ptBR: "Por", .en: "By"],
            "locations": [.ptBR: "Locais", .en: "Locations"],
            "open": [.ptBR: "Abrir", .en: "Open"],
            "eject": [.ptBR: "Ejetar", .en: "Eject"],
            "remove_favorites": [.ptBR: "Remover dos Favoritos", .en: "Remove from Favorites"],
            "Início": [.ptBR: "Início", .en: "Home"],
            "Área de Trabalho": [.ptBR: "Área de Trabalho", .en: "Desktop"],
            "Documentos": [.ptBR: "Documentos", .en: "Documents"],
            "Filmes": [.ptBR: "Filmes", .en: "Movies"],
            "Imagens": [.ptBR: "Imagens", .en: "Pictures"],
            "Música": [.ptBR: "Música", .en: "Music"],
            "Downloads": [.ptBR: "Downloads", .en: "Downloads"],
            "Aplicativos": [.ptBR: "Aplicativos", .en: "Applications"],
            "Lixeira": [.ptBR: "Lixeira", .en: "Trash"],
            "app_description": [
                .ptBR: "Inspirado no Thunar do XFCE, sem qualquer vínculo com o projeto original.",
                .en: "Inspired by XFCE's Thunar, with no affiliation to the original project.",
            ],
            "Vermelho": [.ptBR: "Vermelho", .en: "Red"],
            "Laranja": [.ptBR: "Laranja", .en: "Orange"],
            "Amarelo": [.ptBR: "Amarelo", .en: "Yellow"],
            "Verde": [.ptBR: "Verde", .en: "Green"],
            "Azul": [.ptBR: "Azul", .en: "Blue"],
            "Roxo": [.ptBR: "Roxo", .en: "Purple"],
            "Cinza": [.ptBR: "Cinza", .en: "Gray"],
            "remove_all": [.ptBR: "Remover Todas", .en: "Remove All"],
            "search_placeholder": [.ptBR: "Buscar", .en: "Search"],
            "rename": [.ptBR: "Renomear", .en: "Rename"],
            "get_info": [.ptBR: "Obter Informações", .en: "Get Info"],
            "open_terminal": [.ptBR: "Abrir no Terminal", .en: "Open in Terminal"],
            "add_favorites": [.ptBR: "Adicionar aos Favoritos", .en: "Add to Favorites"],
            "copy": [.ptBR: "Copiar", .en: "Copy"],
            "cut": [.ptBR: "Recortar", .en: "Cut"],
            "paste": [.ptBR: "Colar", .en: "Paste"],
            "compress": [.ptBR: "Comprimir", .en: "Compress"],
            "move_to_trash": [.ptBR: "Mover para Lixeira", .en: "Move to Trash"],
            "delete_permanently": [.ptBR: "Excluir Permanentemente", .en: "Delete Permanently"],
            "cancel": [.ptBR: "Cancelar", .en: "Cancel"],
            "delete": [.ptBR: "Excluir", .en: "Delete"],
            "new_folder": [.ptBR: "Nova Pasta", .en: "New Folder"],
            "new_file": [.ptBR: "Novo Arquivo", .en: "New File"],
            "search_results_in": [.ptBR: "Resultados em", .en: "Results in"],
            "no_items_found": [.ptBR: "Nenhum item encontrado", .en: "No items found"],
            "try_searching_again": [.ptBR: "Tente buscar por outro nome.", .en: "Try searching for another name."],
            "error": [.ptBR: "Erro", .en: "Error"],
            "hide_hidden": [.ptBR: "Ocultar arquivos ocultos", .en: "Hide hidden files"],
            "show_hidden": [.ptBR: "Mostrar arquivos ocultos", .en: "Show hidden files"],
            "confirm_delete": [.ptBR: "Excluir Permanentemente", .en: "Delete Permanently"],
            "delete_warning_singular": [.ptBR: "'%@' será apagado definitivamente. Esta ação não pode ser desfeita.", .en: "'%@' will be permanently deleted. This action cannot be undone."],
            "delete_warning_plural": [.ptBR: "%d itens serão apagados definitivamente. Esta ação não pode ser desfeita.", .en: "%d items will be permanently deleted. This action cannot be undone."],
            "name": [.ptBR: "Nome", .en: "Name"],
            "date": [.ptBR: "Data", .en: "Date"],
            "size": [.ptBR: "Tamanho", .en: "Size"],
            "item_count_singular": [.ptBR: "item", .en: "item"],
            "item_count_plural": [.ptBR: "itens", .en: "items"],
            "searching": [.ptBR: "Buscando", .en: "Searching"],
            "searching_query": [.ptBR: "Buscando \"%@\"...", .en: "Searching \"%@\"..."],
            "searching_tag": [.ptBR: "Buscando itens com etiqueta \"%@\"...", .en: "Searching items with tag \"%@\"..."],
            "volume_unmounted": [.ptBR: "Volume \"%@\" foi desmontado", .en: "Volume \"%@\" was unmounted"],
            "item_exists": [.ptBR: "Já existe um item com o nome \"%@\" neste local.", .en: "An item named \"%@\" already exists here."],
            "create_folder_error": [.ptBR: "Erro ao criar pasta: %@", .en: "Error creating folder: %@"],
            "create_file_error": [.ptBR: "Não foi possível criar o arquivo.", .en: "Could not create file."],
            "moved_to_trash_singular": [.ptBR: "\"%@\" movido para a Lixeira", .en: "\"%@\" moved to Trash"],
            "moved_to_trash_plural": [.ptBR: "%d itens movidos para a Lixeira", .en: "%d items moved to Trash"],
            "deleted_perm_singular": [.ptBR: "\"%@\" excluído permanentemente", .en: "\"%@\" permanently deleted"],
            "deleted_perm_plural": [.ptBR: "%d itens excluídos permanentemente", .en: "%d items permanently deleted"],
            "compressing": [.ptBR: "Comprimindo \"%@\"...", .en: "Compressing \"%@\"..."],
            "compress_success": [.ptBR: "\"%@\" comprimido com sucesso", .en: "\"%@\" compressed successfully"],
            "extracting": [.ptBR: "Descompactando \"%@\"...", .en: "Extracting \"%@\"..."],
            "extract_success": [.ptBR: "\"%@\" descompactado com sucesso", .en: "\"%@\" extracted successfully"],
            "renamed_to": [.ptBR: "\"%@\" renomeado para \"%@\"", .en: "\"%@\" renamed to \"%@\""],
            "copied_singular": [.ptBR: "\"%@\" copiado", .en: "\"%@\" copied"],
            "copied_plural": [.ptBR: "%d itens copiados", .en: "%d items copied"],
            "cut_singular": [.ptBR: "\"%@\" recortado", .en: "\"%@\" cut"],
            "cut_plural": [.ptBR: "%d itens recortados", .en: "%d items cut"],
            "pasting": [.ptBR: "Colando", .en: "Pasting"],
            "moving": [.ptBR: "Movendo", .en: "Moving"],
            "pasting_singular": [.ptBR: "%@ \"%@\"...", .en: "%@ \"%@\"..."],
            "pasting_plural": [.ptBR: "%@ %d itens...", .en: "%@ %d items..."],
            "paste_success_singular": [.ptBR: "\"%@\" %@ com sucesso", .en: "\"%@\" %@ successfully"],
            "paste_success_plural": [.ptBR: "%d itens %@s com sucesso", .en: "%d items %@ successfully"],
            "no_tag_results": [.ptBR: "Nenhum item encontrado com esta etiqueta", .en: "No items found with this tag"],
            "tag_added_singular": [.ptBR: "Etiqueta \"%@\" adicionada a \"%@\"", .en: "Tag \"%@\" added to \"%@\""],
            "tag_added_plural": [.ptBR: "Etiqueta \"%@\" adicionada a %d itens", .en: "Tag \"%@\" added to %d items"],
            "tag_removed_singular": [.ptBR: "Etiqueta \"%@\" removida de \"%@\"", .en: "Tag \"%@\" removed from \"%@\""],
            "tag_removed_plural": [.ptBR: "Etiqueta \"%@\" removida de %d itens", .en: "Tag \"%@\" removed from %d items"],
            "all_tags_removed_singular": [.ptBR: "Etiquetas removidas de \"%@\"", .en: "Tags removed from \"%@\""],
            "all_tags_removed_plural": [.ptBR: "Etiquetas removidas de %d itens", .en: "Tags removed from %d items"],
            "added_to_favorites": [.ptBR: "\"%@\" adicionado aos Favoritos", .en: "\"%@\" added to Favorites"],
            "removed_from_favorites": [.ptBR: "\"%@\" removido dos Favoritos", .en: "\"%@\" removed from Favorites"],
            "no_items_found_for": [.ptBR: "Nenhum item encontrado para \"%@\"", .en: "No items found for \"%@\""],
            "create": [.ptBR: "Criar", .en: "Create"],
            "error_deleting_item": [.ptBR: "Erro ao excluir: %@", .en: "Error deleting: %@"],
            "pasted": [.ptBR: "colado", .en: "pasted"],
            "moved": [.ptBR: "movido", .en: "moved"],
            "folder_name_placeholder": [.ptBR: "Nome da pasta", .en: "Folder name"],
            "file_name_placeholder": [.ptBR: "Nome do arquivo", .en: "File name"],
            "new_name_placeholder": [.ptBR: "Novo nome", .en: "New name"],
            "location": [.ptBR: "Local", .en: "Where"],
            "created": [.ptBR: "Criado", .en: "Created"],
            "modified": [.ptBR: "Modificado", .en: "Modified"],
            "dimensions": [.ptBR: "Dimensões", .en: "Dimensions"],
            "full_path": [.ptBR: "Caminho completo", .en: "Full path"],
            "close": [.ptBR: "Fechar", .en: "Close"],
            "folder": [.ptBR: "Pasta", .en: "Folder"],
            "file": [.ptBR: "Arquivo", .en: "File"],
            "calculating": [.ptBR: "Calculando...", .en: "Calculating..."],
        ]

        return dict[key]?[lang] ?? key
    }
}

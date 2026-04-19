![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)
# 📚 Calibre_Drive - Calibre Cloud & Kindle Sync

> App para gerenciar bibliotecas Calibre armazenadas na nuvem e facilitar o envio de livros diretamente para o seu Kindle.

---

## 🔍 Visão Geral

O projeto visa preencher a lacuna entre o gerenciamento de bibliotecas do **Calibre** (Desktop) e a mobilidade de dispositivos móveis. Ele permite que você acesse todo o seu acervo pessoal de e-books em qualquer lugar, utilizando provedores de nuvem populares.

## ✨ Funcionalidades (Requisitos Funcionais)

- [ ] **Sincronização em Nuvem:** Conexão nativa com as APIs do **Google Drive** e **OneDrive**.
- [ ] **Banco de Dados Inteligente:** Sincronização e armazenamento local do banco de dados `metadata.db` (SQLite) para consultas rápidas.
- [ ] **Interface Visual:** Listagem de livros completa, exibindo capas e metadados detalhados.
- [ ] **Filtros Avançados:** Organização por **Autor**, **Série** ou **Tags** (etiquetas).
- [ ] **Gestão de Arquivos:** Download de e-books para o dispositivo e integração total com o sistema de compartilhamento do Android (facilitando o envio para o app Kindle).

## 🛠️ Especificações Técnicas (Requisitos Não-Funcionais)

* **Persistência de Dados:** Uso de **SQLite** local para garantir performance na busca.
* **Modo Offline:** Após a primeira sincronização dos metadados, o app permite navegar pela biblioteca sem depender de conexão com a internet.
* **Multiplataforma:** Desenvolvido com **Flutter**, garantindo uma experiência nativa e fluida.

## ⚙️ Configuração do Ambiente

### Google Cloud Console
1. Ativar a **Google Drive API**.
2. Configurar a **OAuth Consent Screen** como `External`.
3. Adicionar o escopo `https://www.googleapis.com/auth/drive.readonly`.
4. Gerar as credenciais de **Android** usando o SHA-1 do comando `./gradlew signingReport`.

---

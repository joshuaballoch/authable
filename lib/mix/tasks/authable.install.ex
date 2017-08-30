defmodule Mix.Tasks.Authable.Install do
  use Mix.Task

  import Macro, only: [camelize: 1, underscore: 1]
  import Mix.Generator
  import Mix.Ecto

  @version Mix.Project.config[:version]
  @shortdoc "Creates default migrations and models inside current application."

  @moduledoc """
  Installs authable migrations and models

  ## Examples

      mix authable.install
  """
  def run([version]) when version in ~w(-v --version) do
    Mix.shell.info "Authable v#{@version}"
  end

  @switches [app_path: :string]

  def run(argv) do
    unless Version.match? System.version, "~> 1.3" do
      Mix.raise " v#{@version} requires at least Elixir v1.3.\n " <>
                "You have #{System.version}. Please update accordingly"
    end

    load_config(argv)
    |> multi_cp
    |> gen_user_migration
    |> gen_token_migration
    |> gen_client_migration
    |> gen_app_migration

    print_ecto_info()
  end

  defp load_config(argv) do
    {parsed, _, _} = OptionParser.parse(argv, switches: @switches)

    Application.get_all_env(:authable)
    |> Enum.into(%{})
    |> Map.put(:timestamp, String.to_integer(timestamp()))
    |> Map.put(:app_path, parsed[:app_path])
  end

  defp multi_cp(%{app_path: app_path} = config) do
    copy_from authable_paths(), "./deps/authable/", "", [], models_to_be_copied(app_path)
    config
  end

  defp models_to_be_copied(app_path) do
    []
    |> conditional_add(:resource_owner, Authable.Model.User, {:eex,  "lib/authable/models/app.ex", Path.join([app_path, lib_path("authable"), "app.ex"])})
    |> conditional_add(:token_store, Authable.Model.Token, {:eex,  "lib/authable/models/token.ex", Path.join([app_path, lib_path("authable"), "token.ex"])})
    |> conditional_add(:client, Authable.Model.Client, {:eex,  "lib/authable/models/client.ex", Path.join([app_path, lib_path("authable"), "client.ex"])})
    |> conditional_add(:app, Authable.Model.App, {:eex,  "lib/authable/models/app.ex", Path.join([app_path, lib_path("authable"), "app.ex"])})
  end

  @user_fields [id: ":uuid, primary_key: true",
                email: ":string",
                password: ":string",
                settings: ":jsonb",
                priv_settings: ":jsonb"]
  @user_constraints [email: "create unique_index(:users, [:email])"]

  defp gen_user_migration(%{resource_owner: Authable.Model.User} = config) do
    gen_migration config, :create, ":users, primary_key: false", fields_to_adds(@user_fields), constraints_to_adds(@constraints_to_adds), "user"
  end

  defp gen_user_migration(%{resource_owner: resource_owner} = config) do
    model_name = module_to_model_name(resource_owner)
    field_adds = @user_fields
                 |> reject_if_exists_in_schema(resource_owner)
                 |> fields_to_adds

    constraint_adds = @user_constraints
                      |> reject_if_exists_in_schema(resource_owner)
                      |> constraints_to_adds

    gen_migration config, :alter, ":#{underscore(model_name)}s", field_adds, constraint_adds, model_name
  end

  @token_fields [id: ":uuid, primary_key: true",
                 name: ":string",
                 value: ":string",
                 expires_at: ":integer",
                 details: ":jsonb",
                 user_id: "references(:users, on_delete: :delete_all, type: :uuid)"]

  @token_constraints [user_id: "create index(:tokens, [:user_id])",
                      value: "create unique_index(:tokens, [:value, :name])"]

  defp gen_token_migration(%{token_store: Authable.Model.Token} = config) do
    field_adds = fields_to_adds(@token_fields)

    constraint_adds = constraints_to_adds(@token_constraints)

    gen_migration config, :create, ":tokens, primary_key: false", field_adds, constraint_adds, "token"
  end

  defp gen_token_migration(%{token_store: token_store} = config) do
    model_name = module_to_model_name(token_store)

    field_adds = @token_fields
                 |> reject_if_exists_in_schema(token_store)
                 |> fields_to_adds

    constraint_adds = @token_constraints
                      |> reject_if_exists_in_schema(token_store)
                      |> constraints_to_adds

    gen_migration(config, :alter, ":#{underscore(model_name)}s", field_adds, constraint_adds, model_name)
  end

  @client_fields [id: ":uuid, primary_key: true",
                  name: ":string",
                  secret: ":string",
                  redirect_url: ":string",
                  settings: ":jsonb",
                  priv_settings: ":jsonb",
                  user_id: "references(:users, on_delete: :delete_all, type: :uuid)"]

  @client_constraints [user_id: "create index(:clients, [:user_id])",
                       secret: "create unique_index(:clients, [:secret])",
                       name: "create unique_index(:clients, [:name])"]

  defp gen_client_migration(%{client: Authable.Model.Client} = config) do
    field_adds = fields_to_adds(@client_fields)

    constraint_adds = constraints_to_adds(@client_constraints)

    gen_migration(config, :create, ":clients, primary_key: false", field_adds, constraint_adds, "client")
  end

  defp gen_client_migration(%{client: client_store} = config) do
    model_name = module_to_model_name(client_store)

    field_adds = @client_fields
                 |> reject_if_exists_in_schema(client_store)
                 |> fields_to_adds

    constraint_adds = @client_constraints
                      |> reject_if_exists_in_schema(client_store)
                      |> constraints_to_adds

    gen_migration(config, :alter, ":#{underscore(model_name)}s", field_adds, constraint_adds, model_name)
  end

  @app_fields [id: ":uuid, primary_key: true",
               scope: ":string",
               user_id: "references(:users, on_delete: :delete_all, type: :uuid)",
               client_id: "references(:clients, on_delete: :delete_all, type: :uuid)"]

  @app_constraints [client_id: "create unique_index(:apps, [:user_id, :client_id])"]

  defp gen_app_migration(%{app: Authable.Model.App} = config) do
    field_adds = fields_to_adds(@app_fields)

    constraint_adds = constraints_to_adds(@app_constraints)

    gen_migration(config, :create, ":apps, primary_key: false", field_adds, constraint_adds, "app")
  end

  defp gen_app_migration(%{app: app_store} = config) do
    model_name = module_to_model_name(app_store)

    field_adds = @app_fields
                 |> reject_if_exists_in_schema(app_store)
                 |> fields_to_adds

    constraint_adds = @app_constraints
                      |> reject_if_exists_in_schema(app_store)
                      |> constraints_to_adds

    gen_migration(config, :alter, ":#{underscore(model_name)}s", field_adds, constraint_adds, model_name)
  end

  @doc """
  Copies files from source dir to target dir
  according to the given map.
  Files are evaluated against EEx according to
  the given binding.
  """
  def copy_from(apps, source_dir, target_dir, binding, mapping) when is_list(mapping) do
    roots = Enum.map(apps, &to_app_source(&1, source_dir))

    for {format, source_file_path, target_file_path} <- mapping do
      source =
        Enum.find_value(roots, fn root ->
          source = Path.join(root, source_file_path)
          if File.exists?(source), do: source
        end) || raise "could not find #{source_file_path} in any of the sources"

      target = Path.join(target_dir, target_file_path)

      contents =
        case format do
          :text -> File.read!(source)
          :eex  -> EEx.eval_file(source, binding)
        end

      Mix.Generator.create_file(target, contents)
    end
  end

  defp to_app_source(path, source_dir) when is_binary(path),
    do: Path.join(path, source_dir)
  defp to_app_source(app, source_dir) when is_atom(app),
    do: Application.app_dir(app, source_dir)

  defp authable_paths do
    [".", :authable]
  end

  defp conditional_add(list, config_name, default, path_to_copy) do
    if Application.get_env(:authable, config_name) == default do
      list ++ [path_to_copy]
    else
      list
    end
  end

  defp lib_path(path \\ "") do
    Path.join ["lib", to_string(Mix.Phoenix.otp_app()), path]
  end

  defp priv_path(path \\ "") do
    Path.join ["priv", to_string(Mix.Phoenix.otp_app()), path]
  end

  defp print_ecto_info do
    Mix.shell.info """
    Before moving on, configure your database in config/dev.exs and run:

        $ mix ecto.create
        $ mix ecto.migrate -r Authable.Repo
    """
    nil
  end

  # Utilities
  #
  defp timestamp do
    {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()
    "#{y}#{pad(m)}#{pad(d)}#{pad(hh)}#{pad(mm)}#{pad(ss)}"
  end

  defp pad(i) when i < 10, do: << ?0, ?0 + i >>
  defp pad(i), do: to_string(i)

  # Migrations Utilities
  #
  embed_template :migration, """
  defmodule <%= inspect @mod %> do
    use Ecto.Migration
    def change do
      <%= @change %>
    end
  end
  """

  defp gen_migration(config, :alter, _, "", _, _), do: config
  defp gen_migration(config, :alter, table_statement, field_adds, constraint_adds, model_name) do
    change = """
    alter table(#{table_statement}) do
    #{field_adds}
        end
        #{constraint_adds}
    """
    do_gen_migration config, "add_authable_fields_to_#{underscore(model_name)}", change
  end

  defp gen_migration(config, :create, table_statement, fields, constraints, model_name) do
    change = """
    create table(#{table_statement}) do
    #{fields}
          timestamps()
        end
    #{constraints}
    """
    do_gen_migration config, "create_#{model_name}", change
  end

  def do_gen_migration(%{timestamp: current_timestamp, app_path: app_path, repo: repo} = config, mig_name, change) do
    path = Path.join(app_path, "priv/repo/migrations")
    file_path = Path.join(path, "#{current_timestamp}_#{underscore(mig_name)}.exs")
    assigns = [mod: Module.concat([repo, Migrations, camelize(mig_name)]), change: change]

    create_file file_path, migration_template(assigns)
    Map.put(config, :timestamp, current_timestamp + 1)
  end

  defp reject_if_exists_in_schema(fields, model) do
    Enum.reject(fields, fn({ field_name, _ }) -> Enum.member?(model.__schema__(:fields), field_name) end)
  end

  defp fields_to_adds(fields) do
    fields
    |> Enum.map(fn({key, val}) -> "      add :#{key}, #{val}" end)
    |> Enum.join("\n")
  end

  defp constraints_to_adds(constraints) do
    constraints
    |> Enum.map(fn {_, val} -> "    " <> val end)
    |> Enum.join("\n")
  end

  defp module_to_model_name(model) do
    model
    |> to_string
    |> String.split(".")
    |> Enum.at(-1)
    |> String.downcase
  end
end

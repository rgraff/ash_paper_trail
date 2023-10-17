defmodule AshPaperTrail.Dumpers.FullDiff do
  def build_changes(attributes, changeset) do
    Enum.reduce(attributes, %{}, fn attribute, changes ->
      Map.put(
        changes,
        attribute.name,
        build_attribute_change(attribute, changeset)
      )
    end)
  end

  def build_attribute_change(%{type: {:array, type}} = attribute, changeset) do
    # a composite array is a union or embedded type which we treat as individual values
    if is_union?(type) || is_embedded?(type) do
      build_composite_array_change(attribute, changeset)

      # a non-composite array is treated as a single value
    else
      build_simple_change(attribute, changeset)
    end
  end

  def build_attribute_change(attribute, changeset) do
    # embedded types are created, updated, destroyed, and have their individual attributes tracked
    if is_embedded?(attribute.type) do
      build_embedded_change(attribute, changeset)

      # non-embedded types are treated as a single value
    else
      build_simple_change(attribute, changeset)
    end
  end

  # A simple attribute change will be represented as a map:
  #
  #   %{ to: value }
  #   %{ from: value, to: value }
  #   %{ unchange: value }
  #
  # if the attribute is a union, then there will also be a type key
  def build_simple_change(attribute, changeset) do
    {data_present, dumped_data} =
      if changeset.action_type == :create do
        {false, nil}
      else
        {true, Ash.Changeset.get_data(changeset, attribute.name) |> dump_value(attribute)}
      end

    case Ash.Changeset.fetch_change(changeset, attribute.name) do
      {:ok, value} ->
        build_simple_change_map(
          data_present,
          dumped_data,
          true,
          dump_value(value, attribute)
        )

      :error ->
        build_simple_change_map(
          data_present,
          dumped_data,
          data_present,
          dumped_data
        )
    end
  end

  # A simple attribute change will be represented as a map:
  #
  #   %{ created: %{ ...attrs... } }
  #   %{ updated: %{ ...attrs... } }
  #   %{ unchanged: %{ ...attrs... } }
  #   %{ destroyed: %{ ...attrs... } }
  #
  # if the attribute is a union, then there will also be a type key.
  # The attrs will be the attributes of the embedded resource treated as simple changes.
  def build_embedded_change(attribute, changeset) do
    dumped_data = Ash.Changeset.get_data(changeset, attribute.name) |> dump_value(attribute)

    case Ash.Changeset.fetch_change(changeset, attribute.name) do
      {:ok, nil} ->
        build_embedded_changes(dumped_data, nil)

      {:ok, value} ->
        build_embedded_changes(dumped_data, dump_value(value, attribute))

      :error ->
        if changeset.action_type == :create do
          %{to: nil}
        else
          build_embedded_changes(dumped_data, dumped_data)
        end
    end
  end

  defp build_embedded_changes(nil, nil), do: %{unchanged: nil}

  defp build_embedded_changes(nil, %{} = value),
    do: %{created: build_embedded_attribute_changes(%{}, value)}

  defp build_embedded_changes(%{} = data, nil),
    do: %{destroyed: build_embedded_attribute_changes(data, %{})}

  defp build_embedded_changes(%{} = data, data),
    do: %{unchanged: build_embedded_attribute_changes(data, data)}

  defp build_embedded_changes(%{} = data, %{} = value),
    do: %{updated: build_embedded_attribute_changes(data, value)}

  defp build_embedded_attribute_changes(%{} = from_map, %{} = to_map) do
    keys = Map.keys(from_map) ++ Map.keys(to_map)

    for key <- keys,
        into: %{},
        do:
          {key,
           build_simple_change_map(
             Map.has_key?(from_map, key),
             Map.get(from_map, key),
             Map.has_key?(to_map, key),
             Map.get(to_map, key)
           )}
  end

  # A composite attribute change will be represented as a map:
  #
  #   %{ to: [ %{}, %{}, %{}] }
  #   %{ unchanged: [ %{}, %{}, %{}] }
  #
  # Each element of the array will be represented as a simple change or an embedded change.
  # It will incude a union key if applicable.  Embedded resources with primary_keys will also
  # include an `index` key set to `%{from: x, to: y}` or `%{to: x}` or `%{ucnhanged: x}`.
  def build_composite_array_change(attribute, changeset) do
    data = Ash.Changeset.get_data(changeset, attribute.name)
    dumped_data = dump_value(data, attribute)

    {data_indexes, data_lookup, data_ids} =
      Enum.zip(List.wrap(data), List.wrap(dumped_data))
      |> Enum.with_index(fn {data, dumped_data}, index -> {index, data, dumped_data} end)
      |> Enum.reduce({%{}, %{}, MapSet.new()}, fn {index, data, dumped_data}, {data_indexes, data_lookup, data_ids} ->
        primary_keys = primary_keys(data)
        keys = map_get_keys(data, primary_keys)

        {
          Map.put(data_indexes, keys, index),
          Map.put(data_lookup, keys, dumped_data),
          MapSet.put(data_ids, keys)
        }
      end)

    values =
      case Ash.Changeset.fetch_change(changeset, attribute.name) do
        {:ok, values} -> values
        :error -> []
      end

    {dumped_values, dumped_ids} =
      Enum.zip(List.wrap(values), List.wrap(dump_value(values, attribute)))
      |> Enum.with_index(fn {value, dumped_value}, index -> {index, value, dumped_value} end)
      |> Enum.reduce({[], MapSet.new()}, fn {to_index, value, dumped_value}, {dumped_values, dumped_ids} ->
        case primary_keys(value) do
          [] ->
            %{created: build_embedded_attribute_changes(%{}, dumped_value), no_primary_key: true }

          primary_keys ->
            keys = map_get_keys(value, primary_keys)

            dumped_data = Map.get(data_lookup, keys)

            change = build_embedded_changes(dumped_data, dumped_value)
            # change = %{created: build_embedded_attribute_changes(dumped_data, dumped_value) }

            index_change = Map.get(data_indexes, keys) |> build_index_change(to_index)

            {
              [Map.put(change, :index, index_change) | dumped_values],
              MapSet.put(dumped_ids, keys)
            }
        end
      end)

    dumped_values =
      MapSet.difference(data_ids, dumped_ids)
      |> Enum.reduce(dumped_values, fn keys, dumped_values ->
        dumped_data = Map.get(data_lookup, keys)

        change = build_embedded_changes(dumped_data, nil)

        index_change = Map.get(data_indexes, keys) |> build_index_change(nil)

        [Map.put(change, :index, index_change) | dumped_values]
      end)

    if changeset.action_type == :create do
      %{to: sort_composite_array_changes(dumped_values)}
    else
      build_composite_array_changes(dumped_data, dumped_values)
    end
  end

  def build_composite_array_changes(dumped_values, dumped_values), do: %{unchanged: dumped_values}
  def build_composite_array_changes(nil, []), do: %{unchanged: []}
  def build_composite_array_changes(_dumped_data, dumped_values) do
    %{to: sort_composite_array_changes(dumped_values)}
  end

  def build_index_change(nil, to), do: %{to: to}
  def build_index_change(from, from), do: %{unchanged: from}
  def build_index_change(from, to), do: %{from: from, to: to}

  def sort_composite_array_changes(dumped_values) do
    Enum.sort_by(dumped_values, fn change ->
      case change do
        %{destroyed: _embedded, index: %{from: i}} -> [i, 0]
        %{index: %{to: i}} -> [i, 1]
        %{index: %{unchanged: i}} -> [i, 1]
      end
    end)
  end

  defp dump_value(nil, _attribute), do: nil

  defp dump_value(value, attribute) do
    {:ok, dumped_value} = Ash.Type.dump_to_embedded(attribute.type, value, attribute.constraints)
    dumped_value
  end

  defp map_get_keys(resource, keys) do
    Enum.map(keys, &Map.get(resource, &1))
  end

  defp build_simple_change_map(false, _from, _, to), do: %{to: to}
  defp build_simple_change_map(true, from, true, from), do: %{unchanged: from}
  defp build_simple_change_map(true, from, true, to), do: %{from: from, to: to}
  defp build_simple_change_map(true, from, false, _to), do: %{from: from}

  defp is_union?(type) do
    type == Ash.Type.Union or
      (Ash.Type.NewType.new_type?(type) && Ash.Type.NewType.subtype_of(type) == Ash.Type.Union)
  end

  defp is_embedded?(type), do: Ash.Type.embedded_type?(type)

  defp primary_keys(%{__struct__: resource}), do: Ash.Resource.Info.primary_key(resource)
  defp primary_keys(resource) when is_struct(resource), do: Ash.Resource.Info.primary_key(resource)
  defp primary_keys(_resource), do: []
end

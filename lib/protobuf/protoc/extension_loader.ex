defmodule Protobuf.Protoc.ExtensionLoader do
  @moduledoc false

  alias Protobuf.Protoc.{Context, Generator}
  alias Google.Protobuf.Compiler.CodeGeneratorRequest

  alias Google.Protobuf.{
    DescriptorProto,
    EnumValueDescriptorProto,
    EnumValueOptions,
    FieldDescriptorProto,
    FileDescriptorProto,
    MessageOptions
  }

  @spec rewrite_request_with_extensions(Context.t(), CodeGeneratorRequest.t()) ::
          CodeGeneratorRequest.t()
  def rewrite_request_with_extensions(%Context{} = ctx, %CodeGeneratorRequest{} = request) do
    extensions = collect_extensions(ctx, request)
    rewritten_proto_files = Enum.map(request.proto_file, &rewrite_file_desc(ctx, extensions, &1))
    %CodeGeneratorRequest{request | proto_file: rewritten_proto_files}
  end

  defp rewrite_file_desc(%Context{} = ctx, extensions, %FileDescriptorProto{} = file_desc) do
    file_desc
    |> update_in(
      [
        Access.key!(:enum_type),
        Access.all(),
        Access.key!(:value),
        Access.all()
      ],
      &rewrite_enum_value_descriptor(ctx, extensions, &1)
    )
    |> update_in(
      [
        Access.key(:message_type),
        Access.all()
      ],
      &rewrite_message_descriptor(ctx, extensions, &1)
    )
  end

  defp rewrite_enum_value_descriptor(
         _ctx,
         _extensions,
         %EnumValueDescriptorProto{options: nil} = enum_value_desc
       ) do
    enum_value_desc
  end

  defp rewrite_enum_value_descriptor(
         %Context{} = ctx,
         %{} = extensions,
         %EnumValueDescriptorProto{options: %EnumValueOptions{} = options} = enum_value_desc
       ) do
    %EnumValueOptions{__unknown_fields__: unknown_fields, __pb_extensions__: existing_extensions} =
      options

    {unknown_fields_left, new_extensions} =
      Enum.flat_map_reduce(unknown_fields, existing_extensions, fn unknown_field, acc ->
        {tag, _wire_type, value} = unknown_field

        case Map.fetch(extensions, {".google.protobuf.EnumValueOptions", tag}) do
          {:ok, {namespace, field_name}} ->
            ext_mod = Module.concat([Generator.Util.mod_name(ctx, namespace ++ ["PbExtension"])])
            {[], Map.put(acc, {ext_mod, field_name}, value)}

          :error ->
            {[unknown_field, acc]}
        end
      end)

    new_options = %EnumValueOptions{
      options
      | __unknown_fields__: unknown_fields_left,
        __pb_extensions__: new_extensions
    }

    put_in(enum_value_desc.options, new_options)
  end

  defp rewrite_message_descriptor(_ctx, _extensions, %DescriptorProto{options: nil} = desc) do
    desc
  end

  defp rewrite_message_descriptor(ctx, extensions, %DescriptorProto{options: options} = desc) do
    %MessageOptions{__unknown_fields__: unknown_fields, __pb_extensions__: existing_extensions} =
      options

    {unknown_fields_left, new_extensions} =
      Enum.flat_map_reduce(unknown_fields, existing_extensions, fn unknown_field, acc ->
        {tag, _wire_type, value} = unknown_field

        case Map.fetch(extensions, {".google.protobuf.MessageOptions", tag}) do
          {:ok, {namespace, field_name}} ->
            ext_mod = Module.concat([Generator.Util.mod_name(ctx, namespace ++ ["PbExtension"])])
            {[], Map.put(acc, {ext_mod, field_name}, value)}

          :error ->
            {[unknown_field, acc]}
        end
      end)

    new_options = %MessageOptions{
      options
      | __unknown_fields__: unknown_fields_left,
        __pb_extensions__: new_extensions
    }

    put_in(desc.options, new_options)
  end

  defp collect_extensions(%Context{} = ctx, %CodeGeneratorRequest{} = request) do
    for %FileDescriptorProto{} = file_desc <- request.proto_file,
        namespace = ctx.namespace ++ [file_desc.package],
        %FieldDescriptorProto{} = ext_desc <- file_desc.extension,
        into: %{} do
      {{ext_desc.extendee, ext_desc.number}, {namespace, String.to_atom(ext_desc.name)}}
    end
  end
end

if Rails.env.development? || Rails.env.test?
  env_file = Rails.root.join(".env")

  if File.exist?(env_file)
    File.foreach(env_file) do |line|
      line = line.strip

      next if line.empty? || line.start_with?("#")

      key, value = line.split("=", 2)
      next if key.nil? || value.nil?

      ENV[key.strip] = value.strip
    end
  end
end
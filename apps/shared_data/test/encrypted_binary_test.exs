defmodule SharedData.Encrypted.BinaryTest do
  use ExUnit.Case, async: true

  alias SharedData.Encrypted.Binary, as: EncryptedBinary

  describe "encryption and decryption" do
    test "encrypts and decrypts data correctly" do
      original_data = "sensitive_api_key_12345"

      # Simulate Ecto.Type behavior
      {:ok, encrypted} = EncryptedBinary.cast(original_data)
      {:ok, db_value} = EncryptedBinary.dump(encrypted)

      # Verify encrypted value is different from original
      assert db_value != original_data

      # Decrypt and verify
      {:ok, decrypted} = EncryptedBinary.load(db_value)
      assert decrypted == original_data
    end

    test "encrypted value is not readable" do
      original_data = "my_secret_key"

      {:ok, encrypted} = EncryptedBinary.cast(original_data)
      {:ok, db_value} = EncryptedBinary.dump(encrypted)

      # Encrypted value should not contain original data
      assert not String.contains?(db_value, original_data)
    end

    test "handles empty strings" do
      original_data = ""

      {:ok, encrypted} = EncryptedBinary.cast(original_data)
      {:ok, db_value} = EncryptedBinary.dump(encrypted)
      {:ok, decrypted} = EncryptedBinary.load(db_value)

      assert decrypted == original_data
    end

    test "handles long API keys" do
      # Typical Binance API key is 64 characters
      original_data = String.duplicate("a", 64)

      {:ok, encrypted} = EncryptedBinary.cast(original_data)
      {:ok, db_value} = EncryptedBinary.dump(encrypted)
      {:ok, decrypted} = EncryptedBinary.load(db_value)

      assert decrypted == original_data
      assert String.length(decrypted) == 64
    end

    test "handles special characters in keys" do
      original_data = "key_with_special!@#$%^&*()_+-={}[]|:;<>?,./"

      {:ok, encrypted} = EncryptedBinary.cast(original_data)
      {:ok, db_value} = EncryptedBinary.dump(encrypted)
      {:ok, decrypted} = EncryptedBinary.load(db_value)

      assert decrypted == original_data
    end

    test "same input produces different ciphertext (IV randomization)" do
      original_data = "same_api_key"

      {:ok, encrypted1} = EncryptedBinary.cast(original_data)
      {:ok, db_value1} = EncryptedBinary.dump(encrypted1)

      {:ok, encrypted2} = EncryptedBinary.cast(original_data)
      {:ok, db_value2} = EncryptedBinary.dump(encrypted2)

      # Even with same input, encrypted values should differ due to IV
      assert db_value1 != db_value2

      # But both should decrypt to same value
      {:ok, decrypted1} = EncryptedBinary.load(db_value1)
      {:ok, decrypted2} = EncryptedBinary.load(db_value2)

      assert decrypted1 == original_data
      assert decrypted2 == original_data
    end
  end

  describe "error handling" do
    test "handles nil values" do
      assert {:ok, nil} = EncryptedBinary.cast(nil)
      assert {:ok, nil} = EncryptedBinary.dump(nil)
      assert {:ok, nil} = EncryptedBinary.load(nil)
    end

    test "rejects invalid input types for cast" do
      assert :error = EncryptedBinary.cast(12345)
      assert :error = EncryptedBinary.cast(%{key: "value"})
      assert :error = EncryptedBinary.cast([:list])
    end
  end

  describe "data integrity" do
    test "maintains data integrity across multiple encrypt/decrypt cycles" do
      original_data = "critical_secret_key_data"

      # Encrypt and decrypt multiple times
      {:ok, encrypted1} = EncryptedBinary.cast(original_data)
      {:ok, db_value1} = EncryptedBinary.dump(encrypted1)
      {:ok, decrypted1} = EncryptedBinary.load(db_value1)

      {:ok, encrypted2} = EncryptedBinary.cast(decrypted1)
      {:ok, db_value2} = EncryptedBinary.dump(encrypted2)
      {:ok, decrypted2} = EncryptedBinary.load(db_value2)

      {:ok, encrypted3} = EncryptedBinary.cast(decrypted2)
      {:ok, db_value3} = EncryptedBinary.dump(encrypted3)
      {:ok, decrypted3} = EncryptedBinary.load(db_value3)

      # Data should remain unchanged after multiple cycles
      assert decrypted3 == original_data
    end

    test "encrypted data can be stored and retrieved" do
      api_key = "test_binance_api_key_1234567890abcdef"
      secret_key = "test_binance_secret_key_0987654321fedcba"

      # Encrypt both keys
      {:ok, enc_api} = EncryptedBinary.cast(api_key)
      {:ok, db_api} = EncryptedBinary.dump(enc_api)

      {:ok, enc_secret} = EncryptedBinary.cast(secret_key)
      {:ok, db_secret} = EncryptedBinary.dump(enc_secret)

      # Simulate database storage (both are binary)
      assert is_binary(db_api)
      assert is_binary(db_secret)

      # Retrieve and decrypt
      {:ok, retrieved_api} = EncryptedBinary.load(db_api)
      {:ok, retrieved_secret} = EncryptedBinary.load(db_secret)

      assert retrieved_api == api_key
      assert retrieved_secret == secret_key
    end
  end

  describe "security properties" do
    test "different keys produce different ciphertexts" do
      key1 = "api_key_1"
      key2 = "api_key_2"

      {:ok, enc1} = EncryptedBinary.cast(key1)
      {:ok, db1} = EncryptedBinary.dump(enc1)

      {:ok, enc2} = EncryptedBinary.cast(key2)
      {:ok, db2} = EncryptedBinary.dump(enc2)

      assert db1 != db2
    end

    test "ciphertext length is appropriate" do
      # AES-256-GCM adds overhead: IV (12 bytes) + Tag (16 bytes) + ciphertext
      original = "short_key"

      {:ok, encrypted} = EncryptedBinary.cast(original)
      {:ok, db_value} = EncryptedBinary.dump(encrypted)

      # Encrypted value should be longer than original due to IV and tag
      assert byte_size(db_value) > byte_size(original)

      # But not excessively long (should be original + ~28 bytes + encoding overhead)
      assert byte_size(db_value) < byte_size(original) + 100
    end
  end
end

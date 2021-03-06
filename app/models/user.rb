require 'elasticsearch/model'
class User < ApplicationRecord
	include Elasticsearch::Model
  	include Elasticsearch::Model::Callbacks

	has_many :requirements
	has_many :students, through: :requirements
	has_many :sponsorship_ds

	attr_accessor :activation_token
  before_save   :downcase_email
  before_create :create_activation_digest
  validates :name, presence: true, length: { maximum: 50 }
  VALID_EMAIL_REGEX = /\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i
  validates :email, presence: true, length: { maximum: 255 },
                    format: { with: VALID_EMAIL_REGEX },
                    uniqueness: { case_sensitive: false }
  has_secure_password
  validates :password, presence: true, length: { minimum: 6 }, allow_nil: true


  def self.search(query)
  	__elasticsearch__.search(
    {
      query: {
        multi_match: {
          query: query,
          fields: ['name']
        }
      }
    }
  )
  end

  settings index: { number_of_shards: 1 } do
  mappings dynamic: 'false' do
    indexes :name, analyzer: 'english'
  end
  end

  # Returns the hash digest of the given string.
  def User.digest(string)
    cost = ActiveModel::SecurePassword.min_cost ? BCrypt::Engine::MIN_COST :
                                                  BCrypt::Engine.cost
    BCrypt::Password.create(string, cost: cost)
  end

  # Returns a random token.
  def self.new_token
    SecureRandom.urlsafe_base64
  end

  # Returns true if the given token matches the digest.
  def authenticated?(attribute, token)
    digest = send("#{attribute}_digest")
    return false if digest.nil?
    BCrypt::Password.new(digest).is_password?(token)
  end

  # Activates an account.
  def activate
    update_attribute(:activated,    true)
    update_attribute(:activated_at, Time.zone.now)
  end

  # Sends activation email.
  def send_activation_email
    UserMailer.account_activation(self).deliver_now
  end

   private

    # Converts email to all lower-case.
    def downcase_email
      self.email = email.downcase
    end

    # Creates and assigns the activation token and digest.
    def create_activation_digest
      self.activation_token  = User.new_token
      self.activation_digest = User.digest(activation_token)
    end

end

# Delete the previous index in Elasticsearch
User.__elasticsearch__.client.indices.delete index: User.index_name rescue nil

# Create the new index with the new mapping
User.__elasticsearch__.client.indices.create \
  index: User.index_name,
  body: { settings: User.settings.to_hash, mappings: User.mappings.to_hash }

# Index all records from the DB to Elasticsearch
User.import

class QuepasaSupport < ActiveRecord::Migration[5.1]
  def up

    # return if it's a new setup
    return if !Setting.find_by(name: 'system_init_done')

    Permission.create_if_not_exists(
      name:        'admin.channel_quepasa',
      note:        'Manage %s',
      preferences: {
        translations: ['Channel - QuePasa']
      },
    )

    Ticket::Article::Type.create_if_not_exists(
      name:          'quepasa personal-message',
      communication: true,
      updated_by_id: 1,
      created_by_id: 1,
    )

  end
end

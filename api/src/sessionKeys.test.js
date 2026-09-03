const { getSessionKeys, MIN_KEY_LENGTH } = require('./sessionKeys')

const strongKey = 'a'.repeat(MIN_KEY_LENGTH)

describe('getSessionKeys', () => {
  beforeEach(() => {
    jest.spyOn(console, 'warn').mockImplementation(() => {})
  })

  afterEach(() => {
    console.warn.mockRestore()
  })

  it('uses the configured key', () => {
    expect(getSessionKeys({ cookieSigningKey: strongKey })).toEqual([strongKey])
  })

  it('supports comma-separated keys for rotation', () => {
    const other = 'b'.repeat(MIN_KEY_LENGTH)
    expect(
      getSessionKeys({ cookieSigningKey: `${strongKey}, ${other}` })
    ).toEqual([strongKey, other])
  })

  it('never falls back to a hardcoded key', () => {
    const keys = getSessionKeys({})
    expect(keys).toHaveLength(1)
    expect(keys[0]).not.toEqual('secretkey1')
    expect(keys[0].length).toBeGreaterThanOrEqual(MIN_KEY_LENGTH)
    expect(getSessionKeys({})).not.toEqual(keys)
  })

  it('throws in production when the key is missing or empty', () => {
    expect(() => getSessionKeys({ NODE_ENV: 'production' })).toThrow(
      /cookieSigningKey/
    )
    expect(() =>
      getSessionKeys({ NODE_ENV: 'production', cookieSigningKey: '' })
    ).toThrow(/cookieSigningKey/)
  })

  it('rejects short keys', () => {
    expect(() => getSessionKeys({ cookieSigningKey: 'secretkey1' })).toThrow(
      /at least/
    )
  })
})

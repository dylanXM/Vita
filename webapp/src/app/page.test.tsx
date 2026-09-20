import { describe, expect, it } from 'vitest'

import Home from './page'

describe('Home', () => {
  it('renders the Vita web application identity', () => {
    const page = Home()
    expect(page.type).toBe('div')
    expect(JSON.stringify(page.props.children)).toContain('Vita Console')
    expect(JSON.stringify(page.props.children)).toContain('AI Companion Web App')
  })
})

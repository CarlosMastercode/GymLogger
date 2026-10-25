import React from 'react'

function App() {

    const [showRegistration, setShowRegistration] = React.useState(false)
    const [contactMethod, setContactMethod] = React.useState('email')
    const [registrationMessage, setRegistrationMessage] = React.useState('')

    async function handleRegistration(event) {
        event.preventDefault()
        setRegistrationMessage('Creating your account...')

        const formData = new FormData(event.currentTarget)

        const request = {
            firstName: formData.get('firstName').trim(),
            lastName: formData.get('lastName').trim(),
            email: contactMethod === 'email'
                ? formData.get('contact').trim()
                : null,
            phoneNumber: contactMethod === 'phone'
                ? formData.get('contact').trim()
                : null,
        }

        try {
            const response = await fetch('https://localhost:7299/api/users/register', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(request),
            })

            const result = await response.json()

            if (!response.ok) {
                setRegistrationMessage(
                    result.error || 'Unable to create your account.'
                )
                return
            }

            setRegistrationMessage(
                `Account created successfully! Your user ID is ${result.id}.`
            )
        } catch {
            setRegistrationMessage(
                'Unable to connect to Gym Logger. Please try again.'
            )
        }
    }

    if (showRegistration) {
        return (
            <main className="app">
                <section className="hero">
                    <p className="hero-eyebrow">YOUR FITNESS. YOUR DATA.</p>

                    <h1>
                        Create your <span>account.</span>
                    </h1>

                    <p className="hero-description">
                        Start tracking your workouts and building better habits.
                    </p>

                    <form className="registration-form" onSubmit={handleRegistration}>
                        <label htmlFor="firstName">First name</label>
                        <input
                            id="firstName"
                            name="firstName"
                            type="text"
                            autoComplete="given-name"
                            required
                        />

                        <label htmlFor="lastName">Last name</label>
                        <input
                            id="lastName"
                            name="lastName"
                            type="text"
                            autoComplete="family-name"
                            required
                        />

                        <label htmlFor="contactMethod">Contact method</label>
                        <select
                            id="contactMethod"
                            name="contactMethod"
                            value={contactMethod}
                            onChange={(event) => setContactMethod(event.target.value)}
                        >
                            <option value="email">Email address</option>
                            <option value="phone">Phone number</option>
                        </select>

                        <label htmlFor="contact">
                            {contactMethod === 'email' ? 'Email address' : 'Phone number'}
                        </label>

                        <input
                            id="contact"
                            name="contact"
                            type={contactMethod === 'email' ? 'email' : 'tel'}
                            autoComplete={contactMethod === 'email' ? 'email' : 'tel'}
                            placeholder={
                                contactMethod === 'email'
                                    ? 'you@example.com'
                                    : '(555) 123-4567'
                            }
                            maxLength={contactMethod === 'email' ? 254 : 20}
                            required
                        />

                        <button className="button button-primary" type="submit">
                            Create Account
                        </button>

                        {registrationMessage && (
                            <p role="status" aria-live="polite">
                                {registrationMessage}
                            </p>
                        )}

                        <button
                            className="button button-primary"
                            type="button"
                            onClick={() => setShowRegistration(false)}
                        >
                            Back
                        </button>
                    </form>
                </section>
            </main>
        )
    }

    return (
        <main className="app">
            <header className="app-header">
                <a className="app-logo" href="/">
                    GYM<span>LOGGER</span>
                </a>
                <button
                    className="button button-primary"
                    type="button"
                    onClick={() => setShowRegistration(true)}
                >
                    Register
                </button>
            </header>

            <section className="hero">
                <p className="hero-eyebrow">YOUR FITNESS. YOUR DATA.</p>

                <h1>
                    Every rep.
                    <br />
                    Every <span>step forward.</span>
                </h1>

                <p className="hero-description">
                    Track your workouts, record every set, and see your progress over time.
                </p>

                <button className="button button-primary" type="button">
                    Get Started
                </button>
            </section>

            <footer className="app-footer">
                Gym Logger <span>·</span> Built for progress.
            </footer>
        </main>
    )
}

export default App

import React from 'react'

function App() {

    const [showVerification, setShowVerification] = React.useState(false)
    const [registrationDetails, setRegistrationDetails] = React.useState(null)
    const [showRegistration, setShowRegistration] = React.useState(false)
    const [contactMethod, setContactMethod] = React.useState('email')
    const [registrationMessage, setRegistrationMessage] = React.useState('')
    const [showDashboard, setShowDashboard] = React.useState(false)
    const [showWorkout, setShowWorkout] = React.useState(false)
    const [showSetLogger, setShowSetLogger] = React.useState(false)
    const [exercises, setExercises] = React.useState([])
    const [selectedExercise, setSelectedExercise] = React.useState(null)
    const [weight, setWeight] = React.useState('')
    const [reps, setReps] = React.useState('')
    const [completedSets, setCompletedSets] = React.useState([])
    const wheelRef = React.useRef(null)

    React.useEffect(() => {
        if (!selectedExercise || !wheelRef.current) return

        const selectedElement = wheelRef.current.querySelector('.selected')

        selectedElement?.scrollIntoView({
            behavior: 'smooth',
            block: 'center',
        })
    }, [selectedExercise])

    React.useEffect(() => {
        if (!showSetLogger) return

        async function loadExercises() {
            try {
                const response = await fetch('https://localhost:7299/api/exercises')

                if (!response.ok) {
                    throw new Error('Failed to load exercises.')
                }

                const data = await response.json()

                setExercises(
                    data.sort((a, b) => a.name.localeCompare(b.name))
                )
            } catch (error) {
                console.error('Error loading exercises:', error)
            }
        }

        loadExercises()
    }, [showSetLogger])

    function handleCompleteSet() {
        const parsedWeight = Number(weight)
        const parsedReps = Number(reps)

        if (weight === '' || reps === '' || parsedWeight < 0 || parsedReps < 1) {
            return
        }

        setCompletedSets((previousSets) => [
            ...previousSets,
            {
                setNumber: previousSets.length + 1,
                weight: parsedWeight,
                reps: parsedReps,
            },
        ])

        setWeight('')
        setReps('')
    }

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

            setRegistrationDetails({
                email: request.email,
                phoneNumber: request.phoneNumber,
                userId: result.id,
            })

            setRegistrationMessage('')
            setShowVerification(true)

        } catch {
            setRegistrationMessage(
                'Unable to connect to Gym Logger. Please try again.'
            )
        }
    }

    async function handleVerification(event) {
        event.preventDefault()

        const formData = new FormData(event.currentTarget)
        const code = formData.get('verificationCode').trim()

        setRegistrationMessage('Verifying your account...')

        try {
            const response = await fetch(
                'https://localhost:7299/api/auth/verify-registration',
                {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify({
                        email: registrationDetails.email,
                        phoneNumber: registrationDetails.phoneNumber,
                        code,
                        stayLoggedIn: false,
                    }),
                }
            )

            const result = await response.json()

            if (!response.ok) {
                setRegistrationMessage(
                    result.error || 'Unable to verify your account.'
                )
                return
            }

            localStorage.setItem('sessionToken', result.sessionToken)
            localStorage.setItem('userId', result.userId)

            setRegistrationMessage('Account verified successfully! You are now signed in.')
            setShowVerification(false)
            setShowDashboard(true)
        } catch {
            setRegistrationMessage(
                'Unable to connect to Gym Logger. Please try again.'
            )
        }
    }

    if (showSetLogger) {
        return (
            <main className="app">
                <header className="app-header">
                    <a className="app-logo" href="/">
                        GYM<span>LOGGER</span>
                    </a>
                </header>

                <section className="hero">
                    <p className="hero-eyebrow">YOUR FITNESS. YOUR DATA.</p>

                    <h1>
                        Choose Your <span>Exercise.</span>
                    </h1>

                    <p className="hero-description">
                        What exercise are you working on?
                    </p>

                    <div className="dashboard-options">
                        <div className="exercise-wheel" ref={wheelRef}>
                            {exercises.map((exercise) => (
                                <button
                                    key={exercise.id}
                                    className={`exercise-wheel-item ${selectedExercise?.id === exercise.id ? 'selected' : ''
                                        }`}
                                    type="button"
                                    onClick={() => {
                                        if (selectedExercise?.id === exercise.id) {
                                            setShowSetLogger(false)
                                            setShowWorkout(true)
                                        } else {
                                            setSelectedExercise(exercise)
                                        }
                                    }}
                                >
                                    {exercise.name}
                                </button>
                            ))}
                        </div>

                        <button
                            className="button button-primary"
                            type="button"
                            onClick={() => {
                                setShowSetLogger(false)
                                setShowDashboard(true)
                            }}
                        >
                            Back to Dashboard
                        </button>
                    </div>
                </section>

                <footer className="app-footer">
                    Gym Logger <span>·</span> Built for progress.
                </footer>
            </main>
        )
    }

    if (showWorkout) {
        return (
            <main className="app">
                <header className="app-header">
                    <a className="app-logo" href="/">
                        GYM<span>LOGGER</span>
                    </a>
                </header>

                <section className="hero">
                    <p className="hero-eyebrow">YOUR FITNESS. YOUR DATA.</p>

                    <h1>
                        Log Your <span>{selectedExercise?.name ?? 'Sets'}</span>
                    </h1>

                    <p className="hero-description">
                        Your next session starts here.
                    </p>

                    <div className="set-entry-form">
                        <label>
                            Weight (lb)
                            <input
                                type="number"
                                min="0"
                                step="0.5"
                                value={weight}
                                onChange={(event) => setWeight(event.target.value)}
                                placeholder="Enter weight"
                            />
                        </label>

                        <label>
                            Reps
                            <input
                                type="number"
                                min="1"
                                step="1"
                                value={reps}
                                onChange={(event) => setReps(event.target.value)}
                                placeholder="Enter reps"
                            />
                        </label>
                    </div>

                    <button
                        className="button button-primary"
                        type="button"
                        onClick={handleCompleteSet}
                    >
                        Complete Set
                    </button>

                    {completedSets.length > 0 && (
                        <div className="completed-sets">
                            <h2>Completed Sets</h2>

                            <table>
                                <thead>
                                    <tr>
                                        <th>Set</th>
                                        <th>Weight (lb)</th>
                                        <th>Reps</th>
                                    </tr>
                                </thead>

                                <tbody>
                                    {completedSets.map((set) => (
                                        <tr key={set.setNumber}>
                                            <td>{set.setNumber}</td>
                                            <td>{set.weight}</td>
                                            <td>{set.reps}</td>
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                        </div>
                    )}

                    <div className="dashboard-options">
                        <button
                            className="button button-primary"
                            type="button"
                            onClick={() => {
                                setShowWorkout(false)
                                setShowDashboard(false)
                                setShowSetLogger(true)
                            }}
                        >
                            Log a Set
                        </button>

                        <button
                            className="button button-primary"
                            type="button"
                            onClick={() => {
                                setShowWorkout(false)
                                setShowDashboard(true)
                            }}
                        >
                            Back to Dashboard
                        </button>
                    </div>
                </section>

                <footer className="app-footer">
                    Gym Logger <span>·</span> Built for progress.
                </footer>
            </main>
        )
    }

    if (showDashboard) {
        return (
            <main className="app">
                <header className="app-header">
                    <a className="app-logo" href="/">
                        GYM<span>LOGGER</span>
                    </a>
                </header>

                <section className="hero">
                    <p className="hero-eyebrow">YOUR FITNESS. YOUR DATA.</p>

                    <h1>
                        Welcome to <span>Gym Logger.</span>
                    </h1>

                    <p className="hero-description">
                        What would you like to do today?
                    </p>

                    <div className="dashboard-options">
                        <button
                            className="button button-primary"
                            type="button"
                            onClick={() => setShowWorkout(true)}
                        >
                            Start Session
                        </button>

                        <button
                            className="button button-primary"
                            type="button"
                        >
                            View Prior Sessions
                        </button>

                        <button
                            className="button button-primary"
                            type="button"
                        >
                            See My Progress
                        </button>
                    </div>
                </section>

                <footer className="app-footer">
                    Gym Logger <span>·</span> Built for progress.
                </footer>
            </main>
        )
    }


    if (showVerification) {
        return (
            <main className="app">
                <section className="hero">
                    <p className="hero-eyebrow">ONE LAST STEP</p>

                    <h1>
                        Verify your <span>account.</span>
                    </h1>

                    <p className="hero-description">
                        Enter the six-digit verification code to activate your Gym Logger account.
                    </p>

                    <form className="registration-form" onSubmit={handleVerification}>
                        <label htmlFor="verificationCode">
                            Verification code
                        </label>

                        <input
                            id="verificationCode"
                            name="verificationCode"
                            type="text"
                            inputMode="numeric"
                            pattern="[0-9]{6}"
                            maxLength={6}
                            placeholder="123456"
                            autoComplete="one-time-code"
                            required
                        />

                        <button
                            className="button button-primary"
                            type="submit"
                        >
                            Verify Account
                        </button>

                        <button
                            className="button button-primary"
                            type="button"
                            onClick={() => {
                                setShowVerification(false)
                                setShowRegistration(true)
                            }}
                        >
                            Back to Registration
                        </button>

                        {registrationMessage && (
                            <p role="status" aria-live="polite">
                                {registrationMessage}
                            </p>
                        )}

                    </form>
                </section>
            </main>
        )
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
